from prometheus_client import Counter, Histogram, Gauge

c_update_latest = Counter("minitwit_fct_update_latest_total", "Calls to update_latest")
c_register = Counter("minitwit_fct_register_total", "Calls to register")
c_add_message = Counter("minitwit_fct_add_message_total", "Calls to add_message")

http_requests_total = Counter(
    "minitwit_http_requests_total",
    "Total HTTP requests handled by the application",
    ["method", "route", "status"],
)

http_request_duration_seconds = Histogram(
    "minitwit_http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
)

http_errors_total = Counter(
    "minitwit_http_errors_total",
    "HTTP responses with status code >= 400",
    ["route", "status_class"],
)

db_query_duration_seconds = Histogram(
    "minitwit_db_query_duration_seconds",
    "Database query execution time in seconds",
    buckets=(0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)

g_total_users = Gauge("minitwit_total_users", "Total number of registered users")
g_total_messages = Gauge("minitwit_total_messages", "Total number of messages")
g_total_follows = Gauge("minitwit_total_follows", "Total number of follow relations")
g_avg_followers = Gauge("minitwit_avg_followers", "Average followers per user")
