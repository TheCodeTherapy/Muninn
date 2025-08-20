#define FONT_TEXTURE font_atlas  // Set to the iChannel containing the alphabet texture
#define FONT_SPACING 2.0         // Horizontal character spacing [1 - 2.5]

// Special characters
#define __    32,
#define _EX   33, // " ! "
#define _DBQ  34, // " " "
#define _NUM  35, // " # "
#define _DOL  36, // " $ "
#define _PER  37, // " % "
#define _AMP  38, // " & "
#define _QT   39, // " ' "
#define _LPR  40, // " ( "
#define _RPR  41, // " ) "
#define _MUL  42, // " * "
#define _ADD  43, // " + "
#define _COM  44, // " , "
#define _SUB  45, // " - "
#define _DOT  46, // " . "
#define _DIV  47, // " / "
#define _COL  58, // " : "
#define _SEM  59, // " ; "
#define _LES  60, // " < "
#define _EQ   61, // " = "
#define _GE   62, // " > "
#define _QUE  63, // " ? "
#define _AT   64, // " @ "
#define _LBR  91, // " [ "
#define _ANTI 92, // " \ "
#define _RBR  93, // " ] "
#define _UN   95, // " _ "

// Digits
#define _0 48,
#define _1 49,
#define _2 50,
#define _3 51,
#define _4 52,
#define _5 53,
#define _6 54,
#define _7 55,
#define _8 56,
#define _9 57,
// Uppercase
#define _A 65,
#define _B 66,
#define _C 67,
#define _D 68,
#define _E 69,
#define _F 70,
#define _G 71,
#define _H 72,
#define _I 73,
#define _J 74,
#define _K 75,
#define _L 76,
#define _M 77,
#define _N 78,
#define _O 79,
#define _P 80,
#define _Q 81,
#define _R 82,
#define _S 83,
#define _T 84,
#define _U 85,
#define _V 86,
#define _W 87,
#define _X 88,
#define _Y 89,
#define _Z 90,
// Lowercase
#define _a 97,
#define _b 98,
#define _c 99,
#define _d 100,
#define _e 101,
#define _f 102,
#define _g 103,
#define _h 104,
#define _i 105,
#define _j 106,
#define _k 107,
#define _l 108,
#define _m 109,
#define _n 110,
#define _o 111,
#define _p 112,
#define _q 113,
#define _r 114,
#define _s 115,
#define _t 116,
#define _u 117,
#define _v 118,
#define _w 119,
#define _x 120,
#define _y 121,
#define _z 122,

#define log10(x) int(ceil(.4342944819 * log(x + x*1e-5)))
#define _num_ 0); const int[] str2 = int[](

#define print_char(i) \
  texture2D(FONT_TEXTURE, u + vec2(float(i)-float(x)/FONT_SPACING + FONT_SPACING/8., 15-(i)/16) / 16.).r

#define makeStr(func_name)                             \
  float func_name(vec2 u) {                            \
    if (u.x < 0. || abs(u.y - .03) > .03) return 0.;   \
    const int[] str = int[](                           \

#define _end  0);                                      \
  int x = int(u.x * 16. * FONT_SPACING);               \
  if (x >= str.length()-1) return 0.;                  \
  return print_char(str[x]);                           \
}

#define makeStrF(func_name)                            \
  float func_name(vec2 u, float num, int dec) {        \
    if (u.x < 0. || abs(u.y - .03) > .03) return 0.;   \
    const int[] str1 = int[](

#define makeStrI(func_name)                            \
  float func_name(vec2 u, int num_i) {                 \
    if (u.x < 0. || abs(u.y - .03) > .03) return 0.;   \
    float num = float(num_i);                          \
    const int dec = -1;                                \
    const int[] str1 = int[](

#define _endNum  0);                                   \
  const int l1 = str1.length() - 1;                    \
  int x = int(u.x * 16. * FONT_SPACING);               \
  if (x < l1) return print_char(str1[x]);              \
  bool is_negative = num < 0.;                         \
  if (x == l1) {                                       \
    return print_char(is_negative ? 45 : 32);          \
  }                                                    \
  if (is_negative) num = abs(num);                     \
  int pre = 1 + (1 > log10(num) ? 1 : log10(num));     \
  int s2 = l1 + pre + dec + 1;                         \
  if (x >= s2) {                                       \
    if (x >= s2+str2.length()-1) return 0.;            \
    int n2 = str2[x - s2];                             \
    return print_char(n2);                             \
  }                                                    \
  float d = float(l1 + pre - x);                       \
  if (d == 0.) return print_char(46);                  \
  d = pow(10., d < 0.  ? ++d : d);                     \
  int n = 48 + int(10.*fract(num/.999999/d));          \
  return print_char(n);                                \
}

#define RED     vec3(1.0, 0.3, 0.4)
#define BLUE    vec3(0.5, 1.0, 1.0)
#define YELLOW  vec3(1.0, 1.0, 0.4)
#define ORANGE  (1.0 + cos(text_uv.y * 12.0 + 0.7 + vec3(0.0, 1.0, 2.0)))
#define RAINBOW abs(cos(text_uv.x * 4.0 - time * 2.0 + vec3(5.0, 6.0, 1.0)))
