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