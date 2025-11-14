# Return the nth Fibonacci number
def fib(n):
    grandparent = 0
    parent = 1
    current = n
    if n == 0:
        return 0
    if n == 1:
        return 1

    for num in range(1,n):
        current = parent + grandparent
        grandparent = parent
        parent = current
        
    return current
