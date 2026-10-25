"""Closed-by-default loopback developer service; no fake identity/worker flags."""
from .http_api import Server
from .service import LobbyService


def main():
    server = Server(("127.0.0.1",18769),LobbyService())
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
