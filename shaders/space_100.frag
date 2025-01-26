#version 100
precision highp float;

varying vec2 fragTexCoord;
// varying vec4 fragVertexColor;

uniform vec2 resolution;
uniform float time;

const float TAN30 = 1.0 / sqrt(3.0);

vec3 hue(vec3 col, float a) {
    const vec3 k = vec3(TAN30);
    float c = cos(a);
    return col * c + cross(k, col) * sin(a) + k * dot(k, col) * (1.0 - c);
}

float rand(float n) {
    return fract(sin(n) * 43758.5453123);
}

float rand(vec2 uv) {
    return fract(sin(dot(uv, vec2(12.4124, 48.4124))) * 48512.41241);
}

float noise(vec2 uv) {
    vec2 b = floor(uv);
    return mix(
        mix(rand(b), rand(b + vec2(1.0, 0.0)), 0.5),
        mix(rand(b + vec2(0.0, 1.0)), rand(b + vec2(1.0, 1.0)), 0.5),
        0.5
    );
}

void main(void) {
    vec2 uv = fragTexCoord;
    const float speed = 42.0;
    const int layers = 21;
    float stars = 0.0;
    float fl, s;
    for (int layer = 0; layer < layers; layer++) {
        fl = float(layer);
        s = ((float(layers) * 31.0) - fl * 30.0);
        stars += step(
                0.1,
                pow(
                    abs(noise(mod(vec2(uv.x * s + time * speed - fl * 100.0, uv.y * s), resolution.x))),
                    21.0
                )
            ) * (fl / float(layers));
    }
    vec4 starsColor = vec4(stars) * vec4(0.8, 0.8, 1.0, 1.0);
    starsColor += vec4(uv.x, uv.y, 0.5, 0.2);
    gl_FragColor = starsColor;
}
