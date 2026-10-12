"""Sends the same API request several times at exactly the same moment.

Used by the race-condition tests (for example two simultaneous first loads,
adds, completions or builds) to check that the backend's atomic writes let
only one of them succeed. RequestsLibrary sends requests one after another,
so it cannot test this on its own.
"""

import threading
from concurrent.futures import ThreadPoolExecutor

import requests
from robot.api.deco import keyword, library


@library(scope="GLOBAL")
class ParallelRequests:
    @keyword
    def send_parallel_requests(self, method, url, token, count=2, body=None):
        """Sends ``count`` identical requests at once and returns their status codes.

        All threads wait at a barrier and are released together, so the
        requests reach the backend as close to simultaneously as possible.
        """
        count = int(count)
        headers = {"Authorization": f"Bearer {token}"}
        barrier = threading.Barrier(count)

        def send(_):
            barrier.wait()
            response = requests.request(method, url, headers=headers, json=body, timeout=30)
            return response.status_code

        with ThreadPoolExecutor(max_workers=count) as pool:
            return list(pool.map(send, range(count)))


    @keyword
    def send_different_requests_in_parallel(self, token, requests_to_send):
        """Sends several different requests at once and returns their status codes.

        ``requests_to_send`` is a list of ``[method, url, body]`` entries. The
        status codes are returned in the same order as the requests.
        """
        headers = {"Authorization": f"Bearer {token}"}
        barrier = threading.Barrier(len(requests_to_send))

        def send(entry):
            method, url, body = entry
            barrier.wait()
            response = requests.request(method, url, headers=headers, json=body, timeout=30)
            return response.status_code

        with ThreadPoolExecutor(max_workers=len(requests_to_send)) as pool:
            return list(pool.map(send, requests_to_send))