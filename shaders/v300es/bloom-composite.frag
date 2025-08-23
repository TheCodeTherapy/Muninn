#version 300 es
precision highp float;
precision highp sampler2D;

uniform sampler2D originalTexture;
uniform sampler2D bloomTexture;
uniform float bloomStrength;
uniform float exposure;

in vec2 fragTexCoord;
out vec4 fragColor;

void main() {
  vec4 original = texture(originalTexture, fragTexCoord);
  vec4 bloom = texture(bloomTexture, fragTexCoord);

  // additive blending with strength control
  vec3 result = original.rgb + bloom.rgb * bloomStrength;

  // optional exposure/tone mapping
  result = vec3(1.0) - exp(-result * exposure);

  fragColor = vec4(result, original.a);
}
