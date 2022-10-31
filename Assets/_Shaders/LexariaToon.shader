Shader "Lexaria/Toon"
{
	// The properties block of the Unity shader. In this example this block is empty
	// because the output color is predefined in the fragment shader code.
	Properties
	{
		[Header(Texture)]
		[Space(5)]
		[NoScaleOffset] _BaseMap ("Base Map", 2D) = "white"{}
		[NoScaleOffset][Normal] _NormalMap ("Normal Map", 2D) = "bump" {}
		[Space(30)]

		[Header(Parameter)]
		[Space(5)]
		[Space(30)]

		[Header(Switch)]
		[Space(5)]
		[Toggle(_NORMALMAP)] _EnableNormalMap("Enable NormalMap?", float) = 1.0
		_BumpScale ("Bump Scale", float) = 0.0

		[Toggle(_ALPHATEST_ON)] _AlphaTestToggle ("Alpha Clipping", Float) = 0
		_Cutoff ("Alpha Cutoff", Float) = 0.5
	}

	// The SubShader block containing the Shader code. 
	SubShader
	{
		// SubShader Tags define when and under which conditions a SubShader block or
		// a pass is executed.
		Tags
		{
			"RenderType" = "Opaque" "RenderPipeline" = "UniversalRenderPipeline"
		}

		Pass
		{
			Name "LexariaToonForward"
			Tags
			{
				"LightMode" = "UniversalForward"
			}

			HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

			// receive shadow
			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS
			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
			#pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
			#pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
			#pragma multi_compile_fragment _ _SHADOWS_SOFT

			#pragma shader_feature _NORMALMAP

			// Baked Lightmap
			#pragma multi_compile _ LIGHTMAP_ON
			#pragma multi_compile _ DIRLIGHTMAP_COMBINED
			#pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
			#pragma multi_compile _ SHADOWS_SHADOWMASK

			CBUFFER_START(UnityPerMaterial)
			float _BumpScale;
			float4 _BaseMap_ST;
			CBUFFER_END


			TEXTURECUBE(_Cubemap);
			Texture2D _BaseMap, _NormalMap;
			SamplerState sampler_BaseMap, sampler_NormalMap;

			struct Attributes
			{
				float4 positionOS : POSITION;
				float2 uv: TEXCOORD0;
				float2 uv1: TEXCOORD1;
				float3 normalOS: NORMAL;
				float4 tangentOS: TANGENT;
			};

			struct Varyings
			{
				float4 positionCS : SV_POSITION;

				float3 positionWS : TEXCOORD0;
				float2 uv: TEXCOORD1;
				DECLARE_LIGHTMAP_OR_SH(lightmapUV, vertexSH, 2);

				float4 shadowCoord : TEXCOORD3;
				#ifdef _NORMALMAP
				float3 normalWS: TEXCOORD4;
				float3 tangentWS : TEXCOORD5;
				float3 bitangentWS : TEXCOORD6;
				#else
                    float3 normalWS: TEXCOORD4;
				#endif
			};


			Varyings vert(Attributes IN)
			{
				Varyings OUT;
				const VertexPositionInputs vertex_position_inputs = GetVertexPositionInputs(IN.positionOS);
				const VertexNormalInputs vertex_normal_inputs = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);
				OUT.positionWS = vertex_position_inputs.positionWS;


				OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
				OUT.positionCS = vertex_position_inputs.positionCS;
				//      #if UNITY_REVERSED_Z
				// OUT.positionCS.z = min(OUT.positionCS.z, OUT.positionCS.w * UNITY_NEAR_CLIP_VALUE);
				//      #else
				// OUT.positionCS.z = max(OUT.positionCS.z, OUT.positionCS.w * UNITY_NEAR_CLIP_VALUE);
				//      #endif

				#ifdef _NORMALMAP
				OUT.normalWS = float3(vertex_normal_inputs.normalWS);
				OUT.tangentWS = float3(vertex_normal_inputs.tangentWS);
				OUT.bitangentWS = float3(vertex_normal_inputs.bitangentWS);
				#else
                    OUT.normalWS = float3(vertex_normal_inputs.normalWS);
				#endif

				OUT.shadowCoord = GetShadowCoord(vertex_position_inputs);

				#ifdef LIGHTMAP_ON
                    OUTPUT_LIGHTMAP_UV(IN.uv1, unity_LightmapST, OUT.lightmapUV);
				#else
				OUTPUT_SH(OUT.normalWS, OUT.vertexSH);
				#endif


				return OUT;
			}

			half4 frag(Varyings IN) : SV_Target
			{
				// light
				float4 ShadowCoords = float4(0, 0, 0, 0);
				#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
					ShadowCoords = IN.shadowCoord;
				#elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
					ShadowCoords = TransformWorldToShadowCoord( IN.positionWS );
				#endif

				Light mainLight = GetMainLight(ShadowCoords);
				half atten = mainLight.shadowAttenuation * mainLight.distanceAttenuation;
				float4 lightColor = float4(mainLight.color, 1);
				
				// vector
				float3 lightDir = normalize(mainLight.direction);
				float3 viewWS = GetWorldSpaceViewDir(IN.positionWS);
				#ifdef _NORMALMAP
				float3 var_normalMap = UnpackNormalScale(
					SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, IN.uv), _BumpScale);
				float3 normalWS = TransformTangentToWorld(var_normalMap,
														float3x3(IN.tangentWS, IN.bitangentWS, IN.normalWS));
				#else
                    float3 normalWS = normalize(IN.normalWS);
                    // float3 normalWS = float3(1, 1, 1);
				#endif
				normalWS = normalize(normalWS);
				
				float3 halfVector = normalize(viewWS + lightDir);
				float NdotL = saturate(dot(normalWS, lightDir));
				float NdotV = saturate(dot(normalWS, viewWS));
				float VdotH = saturate(dot(viewWS, halfVector));
				float3 R = reflect(-viewWS, normalWS);

				// Lighting Model
				float halfLambert = pow(NdotL * 0.5 + 0.5, 2);

				
				// Sampling
				float4 BaseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);

				float4 finalColor;
				finalColor.rgb = BaseColor.rgb * halfLambert * lightColor.rgb;
				finalColor.a = BaseColor.a;


				return finalColor;
			}
			ENDHLSL
		}
		UsePass "Universal Render Pipeline/Lit/ShadowCaster"
		UsePass "Universal Render Pipeline/Lit/DepthOnly"
		UsePass "Universal Render Pipeline/Lit/DepthNormals"
		UsePass "Universal Render Pipeline/Lit/Meta"
		UsePass "Universal Render Pipeline/Lit/Universal2D"
	}
}