"""Test stub for run-cron: /ok -> 200, /fail -> 500, /slow -> sleeps 3s.
Writes each request's method, path and selected headers to the log file as JSON lines."""
import http.server, json, sys, time

LOG = sys.argv[2]

class H(http.server.BaseHTTPRequestHandler):
    def _handle(self):
        with open(LOG, "a") as f:
            f.write(json.dumps({"method": self.command, "path": self.path,
                                "host": self.headers.get("Host"), "token": self.headers.get("token"),
                                "ua": self.headers.get("User-Agent"),
                                "xfp": self.headers.get("X-Forwarded-Proto")}) + "\n")
        if self.path.startswith("/slow"):
            time.sleep(3)
        code = 500 if self.path.startswith("/fail") else 200
        self.send_response(code)
        self.send_header("Content-Length", "0")
        self.end_headers()
    do_GET = do_POST = do_PUT = do_DELETE = _handle
    def log_message(self, *a):
        pass

http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
