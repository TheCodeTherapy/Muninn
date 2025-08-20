package build
import mu "vendor:microui"

main :: proc() {
    ctx: ^mu.Context
    if mu.begin_window(ctx, "test", {0,0,100,100}, {.NO_CLOSE}) {

    }
}
