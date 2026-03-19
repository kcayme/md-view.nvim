local buffer = require("md-view.buffer")

describe("buffer", function()
  it("M.new returns an instance with a watch method", function()
    local inst = buffer.new({})
    assert.is_not_nil(inst)
    assert.is_function(inst.watch)
  end)
end)
