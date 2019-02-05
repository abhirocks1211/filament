//------------------------------------------------------------------------------
// Directional light evaluation
//------------------------------------------------------------------------------

vec3 sampleSunAreaLight(const vec3 lightDirection) {
#if !defined(TARGET_MOBILE)
    if (frameUniforms.sun.w >= 0.0) {
        // simulate sun as disc area light
        float LoR = dot(lightDirection, shading_reflected);
        float d = frameUniforms.sun.x;
        HIGHP vec3 s = shading_reflected - LoR * lightDirection;
        return LoR < d ?
                normalize(lightDirection * d + normalize(s) * frameUniforms.sun.y) : shading_reflected;
    }
#endif
    return lightDirection;
}

Light getDirectionalLight() {
    Light light;
    // note: lightColorIntensity.w is always premultiplied by the exposure
    light.colorIntensity = frameUniforms.lightColorIntensity;
    light.l = sampleSunAreaLight(frameUniforms.lightDirection);
    light.attenuation = 1.0;
    light.NoL = saturate(dot(shading_normal, light.l));
    return light;
}

void evaluateDirectionalLight(const PixelParams pixel, inout vec3 color) {
#if defined(HAS_SHADOWING)
    vec3 position = getLightSpacePosition();
    vec2 size = vec2(textureSize(light_shadowMap, 0));
    vec2 texelSize = vec2(1.0) / size;

    vec2 offset = vec2(0.5);
    vec2 uv = (position.xy * size) + offset;
    vec2 base = (floor(uv) - offset) * texelSize;
    vec2 st = fract(uv);

    vec2 uw = vec2(3.0 - 2.0 * st.x, 1.0 + 2.0 * st.x);
    vec2 vw = vec2(3.0 - 2.0 * st.y, 1.0 + 2.0 * st.y);

    vec2 u = vec2((2.0 - st.x) / uw.x - 1.0, st.x / uw.y + 1.0);
    vec2 v = vec2((2.0 - st.y) / vw.x - 1.0, st.y / vw.y + 1.0);

    u *= texelSize.x;
    v *= texelSize.y;

    float depth = position.z;

#if defined(TARGET_METAL_ENVIRONMENT)
    color.rgb = vec3(texture(light_shadowMap, float2(base.x, base.y)).r);
#else
    color.rgb = vec3(texture(light_shadowMap, float2(base.x, base.y)).r);
#endif

#endif
}
