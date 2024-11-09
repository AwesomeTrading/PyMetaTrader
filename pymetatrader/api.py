import asyncio
import logging

from .broker import MT5MQBroker
from .client import MT5MQClient

logger = logging.getLogger("PyMetaTrader")


class MetaTrader:
    q_sub: asyncio.Queue

    _broker: MT5MQBroker
    _client: MT5MQClient

    def __init__(self, q=None):
        self.q_sub = q
        self.markets = dict()

        self._broker = MT5MQBroker()
        self._client = MT5MQClient()

    async def start(self):
        self._broker.start()
        await self._client.start()

    async def stop(self):
        await self._broker.stop()
        await self._client.stop()

    async def _request(self, *params: list[str | int]):
        request = ";".join(params)
        response = await self._client.request(request.encode())

        response = response.split("|",1)
        if response[0] == "KO":
            raise RuntimeError(response[1])

        return response[1]

    def _parse_subcribe_data(self, type, data):
        if type == "BARS":
            result = []
            raws = data.split(";")
            for raw in raws:
                if not raw:
                    continue
                symbol, timeframe, bar = raw.split("|", 2)
                bar = self._parse_bar(bar)
                result.append((symbol, timeframe, bar))
            return result

        if type == "QUOTES":
            return self._parse_quotes(data)

        if type == "TICKS":
            return self._parse_ticks(data)

        if type == "REFRESH":
            raws = data.split("\n")
            history_orders = []
            history_deals = []
            orders = []
            trades = []
            for raw in raws:
                event, data = raw.split(" ", 1)
                if not data:
                    continue
                if event == "HISTORY_ORDERS":
                    history_orders.extend(self._parse_orders(data))
                elif event == "HISTORY_DEALS":
                    history_deals.extend(self._parse_deals(data))
                elif event == "ORDERS":
                    orders.extend(self._parse_orders(data))
                elif event == "TRADES":
                    trades.extend(self._parse_trades(data))

            return dict(
                history_orders=history_orders,
                history_deals=history_deals,
                orders=orders,
                trades=trades,
            )

        raise RuntimeError(f"Cannot parse subscribe data: {type} {data}")

    # ----- MARKETS -----
    # --- Time
    async def get_time(self):
        data = await self._request("TIME")
        return float(data)

    # --- Bars
    async def subscribe_bars(self, symbol, timeframe):
        request = "{};{}".format(symbol, timeframe)
        data = await self._request("SUB_BARS", request)
        return True

    async def unsubscribe_bars(self, symbol, timeframe):
        request = "{};{}".format(symbol, timeframe)
        data = await self._request("UNSUB_BARS", request)
        return True

    async def get_bars(self, symbol, timeframe, start, end):
        request = "{};{};{};{}".format(symbol, timeframe, start / 1000, end / 1000)
        raws = await self._request("BARS", request)
        return self._parse_bars(raws)

    def _parse_bars(self, data):
        raws = data.split(";")

        # building status
        if raws[-1] == "building":
            raws.pop()
            building = True
        else:
            building = False

        # parsing
        bars = []
        for raw in raws:
            if not raw:
                continue

            bar = self._parse_bar(raw)
            bars.append(bar)
        return bars, building

    def _parse_bar(self, raw):
        bar = raw.split("|")
        bar[0] = float(bar[0]) * 1000
        for i in range(1, len(bar)):
            bar[i] = float(bar[i])
        return bar

    # --- Symbols
    async def get_markets(self):
        data = await self._request("MARKETS")
        return self._parse_markets(data)

    def _parse_markets(self, data):
        raws = data.split(";")
        markets = []
        for raw in raws:
            markets.append(self._parse_market(raw))

        self.markets = {m["id"]: m for m in markets}
        return markets

    _market_format = dict(
        point=float,
        digits=float,
        minlot=float,
        lotstep=float,
        maxlot=float,
        lotsize=float,
        ticksize=float,
        tickvalue=float,
        swaplong=float,
        swapshort=float,
        swaprollover=int,
    )

    def _parse_market(self, raw):
        market = self._parse_data_dict(raw, self._market_format)
        market["id"] = market["symbol"]
        return market

    # --- Quote
    async def get_quotes(self, symbols=[]):
        quotes = await self._request("QUOTES")
        quotes = self._parse_quotes(quotes)
        if not symbols:
            return quotes

        results = []
        for quote in quotes:
            if quote["symbol"] in symbols:
                results.append(quote)
        return results

    def _parse_quotes(self, data):
        raws = data.split(";")
        quotes = []
        for raw in raws:
            if not raw:
                continue
            quotes.append(self._parse_quote(raw))
        return quotes

    _quote_format = dict(
        open=float,
        high=float,
        low=float,
        close=float,
        volume=float,
        bid=float,
        ask=float,
        last=float,
        spread=float,
        prev_close=float,
        change=float,
        change_percent=float,
    )

    def _parse_quote(self, raw):
        quote = self._parse_data_dict(raw, self._quote_format)
        return quote

    async def subscribe_quotes(self, symbols: list[str]):
        request = ";".join(symbols)
        data = await self._request("SUB_QUOTES", request)
        return True

    async def unsubscribe_quotes(self, symbols: list[str]):
        request = ";".join(symbols)
        data = await self._request("UNSUB_QUOTES", request)
        return True

    # ---- Ticks
    async def subscribe_ticks(self, *symbols):
        request = ";".join(symbols)
        ok = await self._request("SUB_TICKS", request)
        return True

    async def unsubscribe_ticks(self, symbol):
        ok = await self._request("UNSUB_TICKS", symbol)
        return True

    def _parse_ticks(self, data):
        raws = data.split(";")
        ticks = []
        for raw in raws:
            if not raw:
                continue
            ticks.append(self._parse_tick(raw))
        return ticks

    _tick_format = dict(
        bid=float,
        ask=float,
        spread=float,
        at=float,
    )

    def _parse_tick(self, raw):
        tick = self._parse_data_dict(raw, self._tick_format)
        return tick

    # ---- ACCOUNT ----
    # ---- Account
    async def get_account(self):
        data = await self._request("ACCOUNT")
        return self._parse_account(data)

    _account_format = dict(
        id=int,
        deposit=float,
        margin=float,
        leverage=int,
        gmtoffset=int,
    )

    def _parse_account(self, raw):
        return self._parse_data_dict(raw, self._account_format)

    # ---- Fund
    async def get_fund(self):
        data = await self._request("FUND")
        return self._parse_fund(data)

    _fund_format = dict(
        balance=float,
        equity=float,
    )

    def _parse_fund(self, raw):
        fund = self._parse_data_dict(raw, self._fund_format)
        return fund

    # ---- Trades
    async def get_trades(self, symbol=""):
        data = await self._request("TRADES", symbol)
        return self._parse_trades(data)

    async def modify_trade(self, ticket, sl=0, tp=0):
        request = f"{ticket};{sl or 0};{tp or 0}"
        data = await self._request("MODIFY_TRADE", request)
        return True

    async def close_trade(self, ticket):
        data = await self._request("CLOSE_TRADE", ticket)
        return True

    def _parse_trades(self, data):
        raws = data.split(";")
        trades = []
        for raw in raws:
            if not raw:
                continue

            trade = self._parse_trade(raw)
            trades.append(trade)
        return trades

    _trade_format = dict(
        ticket=int,
        open_price=float,
        open_time=float,
        lots=float,
        sl=float,
        tp=float,
        pnl=float,
        swap=float,
    )

    def _parse_trade(self, raw):
        trade = self._parse_data_dict(raw, self._trade_format)
        trade["open_time"] = trade["open_time"] * 1000
        return trade

    # ---- Deals
    async def get_deals(self, symbol="", fromdate=0):
        request = "{};{}".format(symbol, fromdate)
        data = await self._request("DEALS", request)
        return self._parse_deals(data)

    def _parse_deals(self, data):
        raws = data.split(";")
        deals = []
        for raw in raws:
            if not raw:
                continue
            deal = self._parse_deal(raw)
            if deal:
                deals.append(deal)
        return deals

    _deal_format = dict(
        ticket=int,
        order=int,
        position=int,
        price=float,
        time=float,
        lots=float,
        sl=float,
        tp=float,
        swap=float,
        pnl=float,
        commission=float,
    )

    def _parse_deal(self, raw):
        deal = self._parse_data_dict(raw, self._deal_format)
        if deal["type"] == "DEAL_TYPE_BALANCE":
            return None

        deal["time"] = deal["time"] * 1000
        return deal

    # ---- Orders
    async def get_open_orders(self):
        data = await self._request("ORDERS")
        return self._parse_orders(data)

    def _parse_orders(self, data):
        raws = data.split(";")
        orders = []
        for raw in raws:
            if not raw:
                continue

            order = self._parse_order(raw)
            orders.append(order)
        return orders

    _order_format = dict(
        ticket=int,
        position=int,
        open_price=float,
        open_time=float,
        close_time=float,
        lots=float,
        sl=float,
        tp=float,
        expiration=float,
    )

    def _parse_order(self, raw):
        order = self._parse_data_dict(raw, self._order_format)
        order["open_time"] = order["open_time"] * 1000
        order["close_time"] = order["close_time"] * 1000
        order["expiration"] = order["expiration"] * 1000
        return order

    async def open_order(self, symbol, type, lots, price, sl=0, tp=0, comment=""):
        request = f"{symbol};{type};{lots};{price or 0};{sl or 0};{tp or 0};{comment}"
        ticket = await self._request("OPEN_ORDER", request)
        return int(ticket)

    async def modify_order(self, ticket, price, sl=0, tp=0, expiration=0):
        request = f"{ticket};{price or 0};{sl or 0};{tp or 0};{expiration or 0}"
        data = await self._request("MODIFY_ORDER", request)
        return True

    async def cancel_order(self, ticket):
        data = await self._request("CANCEL_ORDER", ticket)
        return True

    # helpers
    def _parse_data_dict(self, raws, format):
        raws = raws.split("|")
        result = dict()
        for raw in raws:
            key, val = raw.split("=", 1)
            type = format.get(key, str)
            try:
                result[key] = type(val)
            except:
                raise RuntimeError(
                    f"Cannot parse value {val} by key {key}, "
                    f"type {type} for data {data}"
                )
        return result
