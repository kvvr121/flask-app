from flask import Flask, request, jsonify, g
import time
import os
import logging
from prometheus_client import Counter, Histogram, Gauge, generate_latest, CONTENT_TYPE_LATEST
import redis
import psycopg2
from psycopg2 import pool
import boto3
from datetime import datetime

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Prometheus metrics
REQUEST_COUNT = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
REQUEST_LATENCY = Histogram('http_request_duration_seconds', 'HTTP request latency', ['method', 'endpoint'])
ACTIVE_CONNECTIONS = Gauge('flask_app_active_connections', 'Active connections')

# Database connection pool
db_pool = None

def init_db_pool():
    global db_pool
    try:
        db_url = os.getenv('DATABASE_URL', 'postgresql://flaskuser:password@localhost:5432/flaskapp')
        db_pool = psycopg2.pool.SimpleConnectionPool(1, 20, db_url)
        logger.info("Database connection pool initialized")
    except Exception as e:
        logger.error(f"Failed to initialize database pool: {e}")

def get_db_connection():
    if db_pool:
        return db_pool.getconn()
    return None

def return_db_connection(conn):
    if db_pool and conn:
        db_pool.putconn(conn)

# Redis connection
redis_client = None

def init_redis():
    global redis_client
    try:
        redis_url = os.getenv('REDIS_URL', 'redis://localhost:6379')
        redis_client = redis.from_url(redis_url, decode_responses=True, socket_connect_timeout=5, socket_timeout=5)
        redis_client.ping()
        logger.info("Redis connection initialized")
    except Exception as e:
        logger.error(f"Failed to initialize Redis: {e}")
        redis_client = None

# S3 client
s3_client = None

def init_s3():
    global s3_client
    try:
        s3_client = boto3.client('s3', region_name=os.getenv('AWS_REGION', 'us-west-2'))
        logger.info("S3 client initialized")
    except Exception as e:
        logger.error(f"Failed to initialize S3 client: {e}")

@app.before_request
def before_request():
    g.start_time = time.time()
    ACTIVE_CONNECTIONS.inc()

@app.after_request
def after_request(response):
    # Record metrics
    if hasattr(g, 'start_time'):
        duration = time.time() - g.start_time
        REQUEST_LATENCY.labels(method=request.method, endpoint=request.endpoint).observe(duration)
        REQUEST_COUNT.labels(method=request.method, endpoint=request.endpoint, status=response.status_code).inc()
    
    ACTIVE_CONNECTIONS.dec()
    return response

@app.route('/')
def home():
    return jsonify({
        "message": "Hello from Flask!",
        "timestamp": datetime.utcnow().isoformat(),
        "version": "1.0.0",
        "environment": os.getenv('FLASK_ENV', 'development')
    })

@app.route('/about')
def about():
    return jsonify({
        "message": "This is the About page.",
        "timestamp": datetime.utcnow().isoformat(),
        "features": [
            "Docker containerization",
            "Kubernetes orchestration",
            "Prometheus monitoring",
            "Redis caching",
            "PostgreSQL database",
            "AWS S3 storage",
            "CI/CD pipeline"
        ]
    })

@app.route('/health')
def health():
    """Health check endpoint for Kubernetes"""
    health_status = {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
        "checks": {}
    }
    
    # Check database
    try:
        conn = get_db_connection()
        if conn:
            cursor = conn.cursor()
            cursor.execute("SELECT 1")
            cursor.close()
            return_db_connection(conn)
            health_status["checks"]["database"] = "healthy"
        else:
            health_status["checks"]["database"] = "unhealthy"
            health_status["status"] = "unhealthy"
    except Exception as e:
        health_status["checks"]["database"] = f"unhealthy: {str(e)}"
        health_status["status"] = "unhealthy"
    
    # Check Redis (non-critical)
    try:
        if redis_client:
            redis_client.ping()
            health_status["checks"]["redis"] = "healthy"
        else:
            health_status["checks"]["redis"] = "unhealthy"
    except Exception as e:
        health_status["checks"]["redis"] = f"unhealthy: {str(e)}"
    
    # Check S3 (non-critical)
    try:
        if s3_client:
            s3_bucket = os.getenv('S3_BUCKET', 'flask-app-data')
            s3_client.head_bucket(Bucket=s3_bucket)
            health_status["checks"]["s3"] = "healthy"
        else:
            health_status["checks"]["s3"] = "unhealthy"
    except Exception as e:
        health_status["checks"]["s3"] = f"unhealthy: {str(e)}"
    
    status_code = 200 if health_status["status"] == "healthy" else 503
    return jsonify(health_status), status_code

@app.route('/ready')
def ready():
    """Readiness check endpoint for Kubernetes"""
    return jsonify({
        "status": "ready",
        "timestamp": datetime.utcnow().isoformat()
    }), 200

@app.route('/metrics')
def metrics():
    """Prometheus metrics endpoint"""
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}

@app.route('/api/data')
def get_data():
    """API endpoint that uses database and Redis"""
    try:
        # Try to get data from Redis cache first
        cache_key = "api_data"
        if redis_client:
            cached_data = redis_client.get(cache_key)
            if cached_data:
                return jsonify({
                    "data": cached_data,
                    "source": "cache",
                    "timestamp": datetime.utcnow().isoformat()
                })
        
        # If not in cache, get from database
        conn = get_db_connection()
        if conn:
            cursor = conn.cursor()
            cursor.execute("SELECT id, name, created_at FROM sample_data ORDER BY created_at DESC LIMIT 10")
            rows = cursor.fetchall()
            cursor.close()
            return_db_connection(conn)
            
            data = [{"id": row[0], "name": row[1], "created_at": row[2].isoformat()} for row in rows]
            
            # Cache the result in Redis
            if redis_client and data:
                redis_client.setex(cache_key, 300, str(data))  # Cache for 5 minutes
            
            return jsonify({
                "data": data,
                "source": "database",
                "timestamp": datetime.utcnow().isoformat()
            })
        else:
            return jsonify({"error": "Database connection not available"}), 503
            
    except Exception as e:
        logger.error(f"Error in get_data: {e}")
        return jsonify({"error": "Internal server error"}), 500

@app.route('/api/upload', methods=['POST'])
def upload_file():
    """API endpoint for file upload to S3"""
    try:
        if 'file' not in request.files:
            return jsonify({"error": "No file provided"}), 400
        
        file = request.files['file']
        if file.filename == '':
            return jsonify({"error": "No file selected"}), 400
        
        if s3_client:
            s3_bucket = os.getenv('S3_BUCKET', 'flask-app-data')
            file_key = f"uploads/{datetime.utcnow().strftime('%Y/%m/%d')}/{file.filename}"
            
            s3_client.upload_fileobj(file, s3_bucket, file_key)
            
            return jsonify({
                "message": "File uploaded successfully",
                "file_key": file_key,
                "timestamp": datetime.utcnow().isoformat()
            })
        else:
            return jsonify({"error": "S3 client not available"}), 503
            
    except Exception as e:
        logger.error(f"Error in upload_file: {e}")
        return jsonify({"error": "Internal server error"}), 500

@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Not found"}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({"error": "Internal server error"}), 500

if __name__ == '__main__':
    # Initialize connections
    init_db_pool()
    init_redis()
    init_s3()
    
    # Run the application
    app.run(debug=False, host='0.0.0.0', port=5002)
