from classes.stack import Stack

def is_balanced(input_str):
    s = Stack()
    for char in input_str:
        if char == '(':
            s.push(char)
        elif char == ')':
            if s.size() == 0:
                return False
            else:
                s.pop()
    return s.size() == 0

