import pytest
import json
from unittest.mock import patch, MagicMock
from app import app

@pytest.fixture
def client():
    app.config['TESTING'] = True
    with app.test_client() as client:
        yield client

def test_home_endpoint(client):
    """Test the home endpoint"""
    response = client.get('/')
    assert response.status_code == 200
    
    data = json.loads(response.data)
    assert 'message' in data
    assert data['message'] == 'Hello from Flask!'
    assert 'timestamp' in data
    assert 'version' in data
    assert 'environment' in data

def test_about_endpoint(client):
    """Test the about endpoint"""
    response = client.get('/about')
    assert response.status_code == 200
    
    data = json.loads(response.data)
    assert 'message' in data
    assert 'features' in data
    assert isinstance(data['features'], list)
    assert len(data['features']) > 0

def test_health_endpoint(client):
    """Test the health endpoint"""
    with patch('app.get_db_connection') as mock_db, \
         patch('app.redis_client') as mock_redis, \
         patch('app.s3_client') as mock_s3:
        
        # Mock successful connections
        mock_db.return_value = MagicMock()
        mock_redis.ping.return_value = True
        mock_s3.head_bucket.return_value = {}
        
        response = client.get('/health')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert data['status'] == 'healthy'
        assert 'database' in data['checks']
        assert 'redis' in data['checks']
        assert 's3' in data['checks']

def test_ready_endpoint(client):
    """Test the ready endpoint"""
    response = client.get('/ready')
    assert response.status_code == 200
    
    data = json.loads(response.data)
    assert data['status'] == 'ready'

def test_metrics_endpoint(client):
    """Test the metrics endpoint"""
    response = client.get('/metrics')
    assert response.status_code == 200
    assert response.content_type == 'text/plain; version=0.0.4; charset=utf-8'

def test_get_data_endpoint_with_cache(client):
    """Test the get_data endpoint with Redis cache"""
    with patch('app.redis_client') as mock_redis:
        mock_redis.get.return_value = 'cached_data'
        
        response = client.get('/api/data')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert data['source'] == 'cache'
        assert data['data'] == 'cached_data'

def test_get_data_endpoint_with_database(client):
    """Test the get_data endpoint with database fallback"""
    with patch('app.redis_client') as mock_redis, \
         patch('app.get_db_connection') as mock_db, \
         patch('app.return_db_connection') as mock_return_db:
        
        # Mock Redis cache miss
        mock_redis.get.return_value = None
        
        # Mock database connection and query
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_cursor.fetchall.return_value = [(1, 'test', '2023-01-01 00:00:00')]
        mock_conn.cursor.return_value = mock_cursor
        mock_db.return_value = mock_conn
        
        response = client.get('/api/data')
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert data['source'] == 'database'
        assert isinstance(data['data'], list)

def test_upload_file_success(client):
    """Test successful file upload"""
    with patch('app.s3_client') as mock_s3:
        mock_s3.upload_fileobj.return_value = None
        
        response = client.post('/api/upload', 
                             data={'file': (MagicMock(filename='test.txt'), 'test content')})
        assert response.status_code == 200
        
        data = json.loads(response.data)
        assert data['message'] == 'File uploaded successfully'
        assert 'file_key' in data

def test_upload_file_no_file(client):
    """Test file upload with no file"""
    response = client.post('/api/upload')
    assert response.status_code == 400
    
    data = json.loads(response.data)
    assert 'error' in data

def test_404_error(client):
    """Test 404 error handling"""
    response = client.get('/nonexistent')
    assert response.status_code == 404
    
    data = json.loads(response.data)
    assert 'error' in data

def test_prometheus_metrics_increment(client):
    """Test that Prometheus metrics are incremented"""
    with patch('app.REQUEST_COUNT') as mock_counter, \
         patch('app.REQUEST_LATENCY') as mock_histogram:
        
        response = client.get('/')
        assert response.status_code == 200
        
        # Verify metrics were called
        mock_counter.labels.assert_called()
        mock_histogram.labels.assert_called()
