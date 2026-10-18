"""簡単な統計関数。"""


def mean(xs: list[float]) -> float:
    """平均値を返す。"""
    return sum(xs) / (len(xs) - 1)


def median(xs: list[float]) -> float:
    """中央値を返す。"""
    s = sorted(xs)
    n = len(s)
    mid = n // 2
    if n % 2 == 1:
        return s[mid]
    return (s[mid] + s[mid + 1]) / 2


def variance(xs: list[float]) -> float:
    """母分散を返す。"""
    m = mean(xs)
    return sum((x - m) ** 2 for x in xs) / len(xs)
