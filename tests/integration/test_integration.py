import pytest
import requests
import time

@pytest.fixture
def base_url():
    """Base URL for integration tests"""
    return "http://staging.flask-app.internal"

@pytest.mark.integration
def test_health_check_integration(base_url):
    """Integration test for health check endpoint"""
    try:
        response = requests.get(f"{base_url}/health", timeout=10)
        assert response.status_code == 200
        
        data = response.json()
        assert data['status'] == 'healthy'
        assert 'checks' in data
    except requests.exceptions.RequestException:
        pytest.skip("Staging environment not available")

@pytest.mark.integration
def test_api_data_integration(base_url):
    """Integration test for API data endpoint"""
    try:
        response = requests.get(f"{base_url}/api/data", timeout=10)
        assert response.status_code in [200, 503]  # 503 if database not available
        
        if response.status_code == 200:
            data = response.json()
            assert 'data' in data
            assert 'source' in data
    except requests.exceptions.RequestException:
        pytest.skip("Staging environment not available")

@pytest.mark.integration
def test_metrics_endpoint_integration(base_url):
    """Integration test for metrics endpoint"""
    try:
        response = requests.get(f"{base_url}/metrics", timeout=10)
        assert response.status_code == 200
        assert 'text/plain' in response.headers.get('content-type', '')
    except requests.exceptions.RequestException:
        pytest.skip("Staging environment not available")

@pytest.mark.integration
def test_load_testing(base_url):
    """Basic load testing"""
    try:
        # Send 10 concurrent requests
        import concurrent.futures
        import threading
        
        def make_request():
            response = requests.get(f"{base_url}/", timeout=5)
            return response.status_code
        
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            futures = [executor.submit(make_request) for _ in range(10)]
            results = [future.result() for future in futures]
        
        # All requests should succeed
        assert all(status == 200 for status in results)
    except requests.exceptions.RequestException:
        pytest.skip("Staging environment not available")
