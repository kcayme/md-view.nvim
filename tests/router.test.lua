describe("router.resolve_media_path", function()
  local router = require("md-view.server.router")
  local bufdir = "/home/user/docs"

  it("resolves a relative path within bufdir", function()
    local abs = router.resolve_media_path(bufdir, "image.png")
    assert.equals("/home/user/docs/image.png", abs)
  end)

  it("resolves a relative path with ./ prefix", function()
    local abs = router.resolve_media_path(bufdir, "./assets/photo.jpg")
    assert.equals("/home/user/docs/assets/photo.jpg", abs)
  end)

  it("resolves traversal paths to their normalized absolute path", function()
    local abs = router.resolve_media_path(bufdir, "../../docs/demo/image.png")
    assert.equals("/home/docs/demo/image.png", abs)
  end)

  it("allows absolute paths as-is", function()
    local abs = router.resolve_media_path(bufdir, "/tmp/image.png")
    assert.equals("/tmp/image.png", abs)
  end)

  it("returns nil for empty path", function()
    assert.is_nil(router.resolve_media_path(bufdir, ""))
    assert.is_nil(router.resolve_media_path(bufdir, nil))
  end)
end)
