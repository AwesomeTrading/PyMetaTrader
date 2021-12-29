import zmq
import queue
import threading
import random
import string
from datetime import datetime, timezone
from time import sleep


def random_id(length=6):
    return ''.join(random.SystemRandom().choice(string.ascii_uppercase +
                                                string.digits)
                   for _ in range(length))


class MetaTrader():
    wait_timeout = 5000
    waiters = dict()

    def __init__(
        self,
        host,
        push_port=32768,
        pull_port=32769,
        sub_port=32770,
        q=None,
    ):
        self.host = host
        self.push_port = push_port
        self.pull_port = pull_port
        self.sub_port = sub_port
        self.url = "tcp://" + self.host + ":"
        self.q_sub = q

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
        self.sub_socket.setsockopt_string(zmq.SUBSCRIBE, "BARS")
        self.sub_socket.setsockopt_string(zmq.SUBSCRIBE, "QUOTES")
        self.sub_socket.setsockopt_string(zmq.SUBSCRIBE, "ORDERS")

        # Bind PUSH Socket to send commands to MetaTrader
        self.push_socket.connect(self.url + str(self.push_port))
        print("[INIT] Ready to send commands to METATRADER (PUSH): " +
              str(self.push_port))

        # Connect PULL Socket to receive command responses from MetaTrader
        self.pull_socket.connect(self.url + str(self.pull_port))
        print("[INIT] Listening for responses from METATRADER (PULL): " +
              str(self.pull_port))

        # Connect SUB Socket to receive market data from MetaTrader
        self.sub_socket.connect(self.url + str(self.sub_port))
        print("[INIT] Listening for market data from METATRADER (SUB): " +
              str(self.sub_port))

        # Initialize POLL set and register PULL and SUB sockets
        self.poller = zmq.Poller()
        self.poller.register(self.pull_socket, zmq.POLLIN)
        self.poller.register(self.sub_socket, zmq.POLLIN)

        self._t_wait()
        self._t_ping()

    def stop(self):
        self.push_socket.close()
        self.pull_socket.close()
        self.sub_socket.close()
        self.poller.unregister(self.pull_socket)
        self.poller.unregister(self.sub_socket)
        self.context.destroy(0)

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

    ### PING
    def _t_ping(self):
        t = threading.Thread(target=self._loop_ping, daemon=False)
        t.start()

    def _loop_ping(self, delay=20):
        while True:
            sleep(delay)
            data = self._request_and_wait(self.push_socket, 'PING')
            if data != "PONG":
                raise RuntimeError("Ping response is invalid")

    ### EVENTS
    def _t_wait(self):
        t = threading.Thread(target=self._loop_wait, daemon=False)
        t.start()

    def _loop_wait(self, timeout=1000):
        # wait for data
        while True:
            sleep(0.1)

            sockets = dict(self.poller.poll(timeout))
            for socket in sockets:
                try:
                    msg = self._recv(socket)
                    if not msg:
                        continue

                    # print("msg ", msg)
                    # sub socket
                    if socket == self.sub_socket:
                        type, data = msg.split(" ", 1)
                        data = self._parse_subcribe_data(type, data)
                        self.q_sub.put((type, data))
                        continue

                    # pull socket
                    ok, id, data = msg.split("|", 2)
                    if id in self.waiters:
                        self.waiters[id].put((ok == "OK", data))
                    else:
                        print("Abandoned message: ", msg)
                except Exception as e:
                    print("Wait socket data error: ", e)

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
            ok, data = q.get(timeout=self.wait_timeout)
        except queue.Empty:
            raise RuntimeError("No data response")
        finally:
            del self.waiters[id]

        if not ok:
            raise RuntimeError(f"Error request[{action} {msg}]: {data}")
        return data

    def _parse_subcribe_data(self, type, data):
        if type == "BARS":
            result = []
            raws = data.split(";")
            for raw in raws:
                symbol, timeframe, bar = raw.split("|", 2)
                bar = self._parse_bar(bar)
                result.append((symbol, timeframe, bar))
            return result

        if type == "QUOTES":
            return self._parse_quotes(data)

        if type == "ORDERS":
            result = []
            raws = data.split(";")
            for raw in raws:
                event, order = raw.split("|", 1)
                order = self._parse_order(order)
                order['status'] = event
                result.append(order)
            return result

        raise RuntimeError(f"Cannot parse subscribe data: {type} {data}")

    ### MARKETS
    # time
    def get_time(self):
        data = self._request_and_wait(self.push_socket, 'TIME')
        return float(data)

    def _parse_fund(self, data):
        raw = data.split('|')
        return dict(
            cash=float(raw[0]),
            value=float(raw[1]),
        )

    # bars
    def subscribe_bars(self, symbol, timeframe):
        symbol = self._parse_broker_symbol(symbol)
        request = "{};{}".format(symbol, timeframe)
        data = self._request_and_wait(self.push_socket, 'SUB_BARS', request)
        return True

    def unsubscribe_bars(self, symbol, timeframe):
        symbol = self._parse_broker_symbol(symbol)
        request = "{};{}".format(symbol, timeframe)
        data = self._request_and_wait(self.push_socket, 'UNSUB_BARS', request)
        return True

    def get_bars(self, symbol, timeframe, start, end):
        symbol = self._parse_broker_symbol(symbol)
        request = "{};{};{};{}".format(symbol, timeframe, start, end)
        data = self._request_and_wait(self.push_socket, 'BARS', request)
        return self._parse_bars(data)

    def _parse_bars(self, data):
        # data = data.split('|', 2)[2]
        raws = data.split(';')
        bars = []
        for raw in raws:
            if not raw:
                continue

            bar = self._parse_bar(raw)
            bars.append(bar)
        return bars

    def _parse_bar(self, raw):
        bar = raw.split('|')
        bar[0] = float(bar[0]) * 1000
        for i in range(1, len(bar)):
            bar[i] = float(bar[i])
        return bar

    # symbols
    def get_markets(self):
        data = self._request_and_wait(self.push_socket, 'MARKETS')
        return self._parse_markets(data)

    def _parse_markets(self, data):
        raws = data.split(';')
        markets = []
        for raw in raws:
            markets.append(self._parse_market(raw))
        return markets

    # SYMBOL|SYMBOL_DESCRIPTION|SYMBOL_CURRENCY_BASE|MODE_POINT|MODE_DIGITS|MODE_MINLOT|MODE_LOTSTEP|MODE_MAXLOT|MODE_TICKSIZE|TIME_GMTOFFSET
    _market_keys = [['symbol', str], ['description', str], ['currency', str],
                    ['point', float], ['digits', float], ['minlot', float],
                    ['lotstep', float], ['maxlot', float], ['ticksize', float],
                    ['gmt_offset', float]]

    def _parse_market(self, data):
        market = self._parse_data_by_keys(data, self._market_keys)
        market['symbol'] = market['symbol'][:3] + '/' + market['symbol'][3:]
        return market

    # quote
    def get_quotes(self, symbols=[]):
        quotes = self._request_and_wait(self.push_socket, 'QUOTES')
        quotes = self._parse_quotes(quotes)
        if not symbols:
            return quotes

        results = []
        for quote in quotes:
            if quote['symbol'] in symbols:
                results.append(quote)
        return results

    def _parse_quotes(self, data):
        raws = data.split(';')
        quotes = []
        for raw in raws:
            quotes.append(self._parse_quote(raw))
        return quotes

    # SYMBOL|OPEN|HIGH|LOW|CLOSE|VOLUME|BID|ASK|LAST|SPREAD|PREV_CLOSE|CHANGE|CHANGE_PERCENT
    _quote_keys = [['symbol', str], ['open', float], ['high', float],
                   ['low', float], ['close', float], ['volume', float],
                   ['bid', float], ['ask', float], ['last', float],
                   ['spread', float], ['prev_close', float], ['change', float],
                   ['change_percent', float]]

    def _parse_quote(self, data):
        quote = self._parse_data_by_keys(data, self._quote_keys)
        quote['symbol'] = quote['symbol'][:3] + '/' + quote['symbol'][3:]
        return quote

    def subscribe_quotes(self, symbol):
        symbol = self._parse_broker_symbol(symbol)
        data = self._request_and_wait(self.push_socket, 'SUB_QUOTES', symbol)
        return True

    def unsubscribe_quotes(self, symbol):
        symbol = self._parse_broker_symbol(symbol)
        data = self._request_and_wait(self.push_socket, 'UNSUB_QUOTES', symbol)
        return True

    ### ACCOUNT
    # fund
    def get_fund(self):
        data = self._request_and_wait(self.push_socket, 'FUND')
        return self._parse_fund(data)

    # trades
    def get_trades(self, symbol=''):
        symbol = self._parse_broker_symbol(symbol)
        data = self._request_and_wait(self.push_socket, 'TRADES', symbol)
        return self._parse_orders(data)

    # orders
    def get_open_orders(self):
        data = self._request_and_wait(self.push_socket, 'ORDERS')
        return self._parse_orders(data)

    def _parse_orders(self, data):
        raws = data.split(';')
        orders = []
        for raw in raws:
            if not raw:
                continue

            order = self._parse_order(raw)
            orders.append(order)
        return orders

    # TICKET|SYMBOL|TYPE|OPEN_PRICE|OPEN_TIME|LOT|SL|TP|PNL|COMMISSION|SWAP|EXPIRATION|COMMENT|CLOSE_PRICE|CLOSE_TIME
    _order_keys = [['ticket', int], ['symbol', str], ['type', str],
                   ['open_price', float],
                   ['open_time', float], ['lots', float], ['sl', float],
                   ['tp', float], ['pnl', float], ['commission', float],
                   ['swap', float], ['expiration', float], ['comment', str],
                   ['close_price', float], ['close_time', float]]

    def _parse_order(self, raw):
        order = self._parse_data_by_keys(raw, self._order_keys)
        order['open_time'] = order['open_time'] * 1000
        order['close_time'] = order['close_time'] * 1000
        order['expiration'] = order['expiration'] * 1000
        return order

    def open_order(self, symbol, type, lots, price, sl=0, tp=0, comment=''):
        request = f"{symbol};{type};{lots};{price};{sl};{tp};{comment}"
        ticket = self._request_and_wait(self.push_socket, 'OPEN_ORDER',
                                        request)
        return int(ticket)

    def modify_order(self, ticket, price, sl=0, tp=0, expiration=0):
        request = f"{ticket};{price};{sl};{tp};{expiration}"
        data = self._request_and_wait(self.push_socket, 'MODIFY_ORDER',
                                      request)
        return True

    def close_order(self, ticket):
        data = self._request_and_wait(self.push_socket, 'CLOSE_ORDER', ticket)
        if data != "OK":
            raise RuntimeError(f"Close order {ticket} error: {data}")
        return True

    def cancel_order(self, ticket):
        data = self._request_and_wait(self.push_socket, 'CANCEL_ORDER', ticket)
        if data != "OK":
            raise RuntimeError(f"Cancel order {ticket} error: {data}")
        return True

    ### helpers
    def _parse_broker_symbol(self, symbol: str):
        return symbol.replace("/", "")

    def _parse_data_by_keys(self, data, keys):
        raw = data.split('|')
        result = dict()
        for i in range(0, len(keys)):
            try:
                key = keys[i][0]
                type = keys[i][1]
                result[key] = type(raw[i])
            except:
                raise RuntimeError(
                    f"Cannot parse data {data} by key {key}, type {type} and value {raw[i]}"
                )
        return result
