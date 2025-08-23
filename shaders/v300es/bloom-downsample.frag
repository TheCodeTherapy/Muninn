#version 300 es
precision highp float;
precision highp sampler2D;

uniform sampler2D inputTexture;
uniform vec2 texelSize;
uniform float radius;

in vec2 fragTexCoord;
out vec4 fragColor;

void main() {
  // 13-tap downsample with proper filtering
  vec4 color = vec4(0.0);

  // scale texel size by radius for larger/smaller blur kernel
  vec2 scaledTexelSize = texelSize * radius;

  // center sample (highest weight)
  color += texture(inputTexture, fragTexCoord) * 0.196;

  // plus pattern samples
  color += texture(inputTexture, fragTexCoord + vec2(scaledTexelSize.x, 0.0)) * 0.098;
  color += texture(inputTexture, fragTexCoord + vec2(-scaledTexelSize.x, 0.0)) * 0.098;
  color += texture(inputTexture, fragTexCoord + vec2(0.0, scaledTexelSize.y)) * 0.098;
  color += texture(inputTexture, fragTexCoord + vec2(0.0, -scaledTexelSize.y)) * 0.098;

  // diagonal samples
  color += texture(inputTexture, fragTexCoord + vec2(scaledTexelSize.x, scaledTexelSize.y)) * 0.049;
  color += texture(inputTexture, fragTexCoord + vec2(-scaledTexelSize.x, scaledTexelSize.y)) * 0.049;
  color += texture(inputTexture, fragTexCoord + vec2(scaledTexelSize.x, -scaledTexelSize.y)) * 0.049;
  color += texture(inputTexture, fragTexCoord + vec2(-scaledTexelSize.x, -scaledTexelSize.y)) * 0.049;

  // outer samples for smoother falloff
  color += texture(inputTexture, fragTexCoord + vec2(scaledTexelSize.x * 2.0, 0.0)) * 0.024;
  color += texture(inputTexture, fragTexCoord + vec2(-scaledTexelSize.x * 2.0, 0.0)) * 0.024;
  color += texture(inputTexture, fragTexCoord + vec2(0.0, scaledTexelSize.y * 2.0)) * 0.024;
  color += texture(inputTexture, fragTexCoord + vec2(0.0, -scaledTexelSize.y * 2.0)) * 0.024;

  fragColor = color;
}
