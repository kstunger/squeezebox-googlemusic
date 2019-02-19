#!/usr/bin/env python

"""
A simple proxy server. Usage:
http://hostname:port/p/(URL to be proxied, minus protocol)
For example:
http://localhost:8080/www.google.com
"""
import argparse
from flask import Flask, request, send_file, Response, make_response
from werkzeug.contrib.cache import SimpleCache
import requests
import logging
import io
import os
import re

logging.basicConfig(level=logging.INFO)
LOG = logging.getLogger("main.py")
cache = SimpleCache()

ALLOWED_URL = re.compile(r'.*googleusercontent.com\/.*')


def create_app(debug=False):
    app = Flask(__name__)
    app.debug = debug
    return app


app = create_app()


@app.after_request
def after_request(response):
    response.headers.add('Accept-Ranges', 'bytes')
    return response


def send_file_partial(response):
    """
        Simple wrapper around send_file which handles HTTP 206 Partial Content
        (byte ranges)
    """

    strIO = io.BytesIO(response.content)
    strIO.seek(0)

    range_header = request.headers.get('Range', None)
    if not range_header:
        return send_file(strIO, mimetype=response.headers['Content-Type'])

    size = len(response.content)
    byte1, byte2 = 0, None

    m = re.search(r'(\d+)-(\d*)', range_header)
    g = m.groups()

    if g[0]:
        byte1 = int(g[0])
    if g[1]:
        byte2 = int(g[1])

    length = size - byte1
    if byte2 is not None:
        length = 1 + byte2 - byte1

    strIO.seek(byte1)
    partial = strIO.read(length)

    rv = Response(
        partial,
        206,
        mimetype=response.headers['Content-Type'],
        direct_passthrough=True)
    rv.headers.add(
        'Content-Range',
        'bytes {0}-{1}/{2}'.format(byte1, byte1 + length - 1, size))

    return rv


@app.route('/', defaults={'path': ''})
@app.route('/<path:path>')
def proxy(path):
    url = '{}?{}'.format(
        path,
        request.query_string.decode('utf-8')
    )
    if not ALLOWED_URL.match(path):
        return make_response(("domain is not allowed", 500))

    response = cache.get(url)
    if response is None:
        response = requests.get(url, allow_redirects=True)
        cache.set(url, response, timeout=10*60)

    return send_file_partial(response)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument("--address", help="Listen address", default="0.0.0.0")
    parser.add_argument("--port", help="Listen port", default="8090")
    args = parser.parse_args()
    port = args.port
    address = args.address
    app.run(address, port)
