import zmq
import queue
import threading
import random
import string
from datetime import datetime
from time import sleep


def random_id(length=6):
    return ''.join(random.SystemRandom().choice(string.ascii_uppercase +
                                                string.digits)
                   for _ in range(length))


class MetaTraderAPI():
    wait_timeout = 5000
    waiters = dict()

    def __init__(self, host, push_port=32768, pull_port=32769, sub_port=32770):
        self.host = host
        self.push_port = push_port
        self.pull_port = pull_port
        self.sub_port = sub_port
        self.url = "tcp://" + self.host + ":"

        # ZeroMQ Context
        self.context = zmq.Context()

        # Create Sockets
        self.push_socket = self.context.socket(zmq.PUSH)
        self.push_socket.setsockopt(zmq.SNDHWM, 1)
        # self.push_socket_status = {'state': True, 'latest_event': 'N/A'}

        self.pull_socket = self.context.socket(zmq.PULL)
        self.pull_socket.setsockopt(zmq.RCVHWM, 1)
        # self.pull_socket_status = {'state': True, 'latest_event': 'N/A'}

        self.sub_socket = self.context.socket(zmq.SUB)

        # Bind PUSH Socket to send commands to MetaTrader
        self.push_socket.connect(self.url + str(self.push_port))
        print("[INIT] Ready to send commands to METATRADER (PUSH): " +
              str(self.push_port))

        # Connect PULL Socket to receive command responses from MetaTrader
        self.pull_socket.connect(self.url + str(self.pull_port))
        print("[INIT] Listening for responses from METATRADER (PULL): " +
              str(self.pull_port))

        # Connect SUB Socket to receive market data from MetaTrader
        print("[INIT] Listening for market data from METATRADER (SUB): " +
              str(self.sub_port))
        self.sub_socket.connect(self.url + str(self.sub_port))

        # Initialize POLL set and register PULL and SUB sockets
        self.poller = zmq.Poller()
        self.poller.register(self.pull_socket, zmq.POLLIN)
        self.poller.register(self.sub_socket, zmq.POLLIN)

        self._t_wait()

    def _send(self, socket, data):
        # if self._PUSH_SOCKET_STATUS['state'] == True:
        try:
            socket.send_string(data, zmq.DONTWAIT)
        except zmq.error.Again:
            print("Resource timeout.. please try again.")
        # else:
        #     print('\n[KERNEL] NO HANDSHAKE ON PUSH SOCKET.. Cannot SEND data')

    def _recv(self, socket) -> str:
        # if self._PULL_SOCKET_STATUS['state'] == True:
        try:
            return socket.recv_string(zmq.DONTWAIT)
        except zmq.error.Again:
            print("Resource timeout.. please try again.")
        # else:
        #     print('\r[KERNEL] NO HANDSHAKE ON PULL SOCKET.. Cannot READ data', end='', flush=True)

        return None

    def _t_wait(self):
        t = threading.Thread(target=self._loop_wait, daemon=False)
        t.start()

    def _loop_wait(self, timeout=1000):
        while True:
            sleep(0.1)

            sockets = dict(self.poller.poll(timeout))
            for socket in sockets:
                # try:
                msg = self._recv(socket)

                if not msg:
                    break

                datas = msg.split("|", 2)
                print("datas ", datas)
                id = datas[1]
                data = datas[2]
                if id in self.waiters:
                    self.waiters[id].put(data)
                else:
                    print("Abandoned message: ", msg)
                # except zmq.error.Again:
                #     pass  # resource temporarily unavailable, nothing to print
                # except ValueError:
                #     pass  # No data returned, passing iteration.
                # except UnboundLocalError:
                #     pass  # _symbol may sometimes get referenced before being assigned.

    def _request(self, socket, action, msg=''):
        request_id = random_id()
        request = "{};{};{}".format(action, request_id, msg)
        self._send(socket, request)

        q = queue.Queue()
        self.waiters[request_id] = q
        return request_id, q

    def _request_and_wait(self, socket, action, msg=''):
        id, q = self._request(socket, action, msg)
        try:
            return q.get(self.wait_timeout)
        except queue.Empty:
            del self.waiters[id]
            raise RuntimeError("No data response")

    # bars
    def bars(self, symbol, timeframe, start, end):
        request = "{};{};{};{};{}".format(symbol, timeframe, start, end)
        data = self._request_and_wait(self.push_socket, 'HISTORY', request)
        return self._parse_bars(data)

    def _parse_bars(self, data):
        raws = data.split(';')
        bars = []
        for raw in raws:
            bar = raw.split('|')
            bar[0] = datetime.strptime(bar[0], '%Y.%m.%d %H:%M:%S')
            bars.append(bar)
        return bars

    # symbols
    def symbols(self):
        data = self._request_and_wait(self.push_socket, 'SYMBOLS')
        return self._parse_symbols(data)

    def _parse_symbols(self, data):
        return data.split(";")
