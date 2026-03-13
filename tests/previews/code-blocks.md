# Code Blocks

Inline: `console.log("hello")`

```
Plain code block with no language specified
line 2
line 3
```

```lua
-- Lua code block
local M = {}

function M.setup(opts)
  opts = opts or {}
  print("Hello from Lua")
end

return M
```

```javascript
// JavaScript code block
function fibonacci(n) {
  if (n <= 1) return n;
  return fibonacci(n - 1) + fibonacci(n - 2);
}

console.log(fibonacci(10));
```

```python
# Python code block
def greet(name: str) -> str:
    return f"Hello, {name}!"

if __name__ == "__main__":
    print(greet("World"))
```

```bash
#!/bin/bash
echo "Shell script"
for i in {1..5}; do
  echo "Iteration $i"
done
```
