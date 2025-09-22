import pytest
import requests

@pytest.fixture
def production_url():
    """Production URL for smoke tests"""
    return "https://flask-app.example.com"

@pytest.mark.smoke
def test_production_health_check(production_url):
    """Smoke test for production health check"""
    try:
        response = requests.get(f"{production_url}/health", timeout=10)
        assert response.status_code == 200
        
        data = response.json()
        assert data['status'] == 'healthy'
    except requests.exceptions.RequestException:
        pytest.skip("Production environment not available")

@pytest.mark.smoke
def test_production_home_endpoint(production_url):
    """Smoke test for production home endpoint"""
    try:
        response = requests.get(f"{production_url}/", timeout=10)
        assert response.status_code == 200
        
        data = response.json()
        assert 'message' in data
        assert data['environment'] == 'production'
    except requests.exceptions.RequestException:
        pytest.skip("Production environment not available")

@pytest.mark.smoke
def test_production_ssl_certificate(production_url):
    """Smoke test for SSL certificate"""
    try:
        response = requests.get(f"{production_url}/", timeout=10, verify=True)
        assert response.status_code == 200
    except requests.exceptions.SSLError:
        pytest.fail("SSL certificate validation failed")
    except requests.exceptions.RequestException:
        pytest.skip("Production environment not available")

@pytest.mark.smoke
def test_production_response_time(production_url):
    """Smoke test for response time"""
    try:
        start_time = time.time()
        response = requests.get(f"{production_url}/", timeout=10)
        end_time = time.time()
        
        response_time = end_time - start_time
        assert response.status_code == 200
        assert response_time < 2.0  # Response should be under 2 seconds
    except requests.exceptions.RequestException:
        pytest.skip("Production environment not available")
