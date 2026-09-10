Shader "Custom/WindTree"
{
    Properties
    {
        _MainTex       ("Albedo", 2D)                  = "white" {}
        _Color         ("Color", Color)                = (1,1,1,1)
        _Cutoff        ("Alpha Cutoff", Range(0,1))    = 0.5

        _WindDir       ("Wind Direction XZ", Vector)   = (1,0,0,0)
        _WindStrength  ("Wind Strength", Range(0,2))   = 0.3
        _WindSpeed     ("Wind Speed", Range(0,5))      = 1.5
        _ObjectHeight  ("Object Height", Float)        = 4.0
    }

    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "Queue"="AlphaTest" "DisableBatching"="True" }
        Cull Off

        CGPROGRAM
        #include "UnityCG.cginc"
        #pragma surface surf Lambert vertex:vert alphatest:_Cutoff
        #pragma target 3.0

        sampler2D _MainTex;
        fixed4    _Color;
        float4    _WindDir;
        float     _WindStrength;
        float     _WindSpeed;
        float     _ObjectHeight;

        struct Input { float2 uv_MainTex; };

        void vert(inout appdata_full v)
        {
            float mask  = v.color.r;
            float normH = saturate(v.vertex.y / max(_ObjectHeight, 0.01));
            float wave  = sin(_Time.y * _WindSpeed + v.vertex.x);

            float2 wDir = normalize(_WindDir.xz + 0.001);
            float  bend = wave * _WindStrength * normH * normH * mask;

            v.vertex.x += wDir.x * bend;
            v.vertex.z += wDir.y * bend;
        }

        void surf(Input IN, inout SurfaceOutput o)
        {
            fixed4 c = tex2D(_MainTex, IN.uv_MainTex) * _Color;
            o.Albedo = c.rgb;
            o.Alpha  = c.a;
        }

        ENDCG
    }

    Fallback "Nature/Soft Occlusion Leaves"
}