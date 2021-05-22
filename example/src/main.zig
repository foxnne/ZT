const std = @import("std");
const zt = @import("zt");
usingnamespace @import("imgui");
// ZT includes several custom components to draw/use native types such as
// zig fmt in text and math types.
usingnamespace zt.imguiComponents;

var config: zt.app.ZTLAppConfig = .{
    .init = init,
    .update = update,
    .deinit = deinit,
};

var spriteBuffer: zt.SpriteBuffer = undefined;
var testSprite: zt.Texture = undefined;
var basePath: []const u8 = "";

fn init() void {
    // Use KnownFolders to have a solid reference to the sprite location.
    basePath = (zt.folders.getPath(std.heap.page_allocator, zt.folders.KnownFolder.executable_dir) catch unreachable).?;

    // Get the sprite's location from the basepath, and load a Texture with it, as well as setting the window icon.
    var spriteLocation = std.fs.path.joinZ(std.heap.page_allocator, &[_][]const u8{basePath, "test.png"}) catch unreachable;
    testSprite = zt.Texture.init(spriteLocation) catch unreachable;
    config.icon = spriteLocation;

    // ZT offers a simple sprite buffer to draw batched sprites efficiently. 
    spriteBuffer = zt.SpriteBuffer.init(std.heap.page_allocator);
    // We don't specify a texture because you decide that on flush by passing a texture into the flush.
    spriteBuffer.sprite(10,10,0.5,100,100, zt.math.Vec4.one);
    spriteBuffer.sprite(120,10,0.5,100,100, zt.math.Vec4.one);

    // Enable docking.
    var io = igGetIO();
    io.*.ConfigFlags |= ImGuiConfigFlags_DockingEnable;
}
fn update() void {
    // Bind a texture and then flush the buffer! The buffer will be updated to opengl whenever it is dirtied by clearing
    // or by adding more sprites.
    spriteBuffer.flushStatic(&testSprite);

    // And you can just use imgui anywhere and the app will handle updating imgui state and drawing it.

    if(igBeginMainMenuBar()) {
        if(igBeginMenu("File", true)) {
            igText("Thing 1");
            igText("Thing 2");
            igText("Thing 3");
            igEndMenu();
        }
        igEndMainMenuBar();
    }

    if(igBegin("Testing Window", null, ImGuiWindowFlags_None)) {
        igText("It works!");
    }
    igEnd();
    if(igBegin("Dock Window", null, ImGuiWindowFlags_None)) {
        igText("Docking....");
    }
    igEnd();

}
fn deinit() void {
    testSprite.deinit();
    spriteBuffer.deinit();
}

pub fn main() void {
    zt.app.start(config);
}