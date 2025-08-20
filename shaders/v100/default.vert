#version 100
precision highp float;

attribute vec3 vertexPosition;
attribute vec2 vertexTexCoord;
attribute vec3 vertexNormal;
attribute vec4 vertexColor;

uniform mat4 mvp;
uniform vec4 colDiffuse;

varying vec2 fragTexCoord;
varying vec4 fragVertexColor;

void main() {
  fragTexCoord = vertexTexCoord;
  fragVertexColor = vertexColor;
  gl_Position = mvp * vec4(vertexPosition, 1.0);
}
