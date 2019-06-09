Shader "Silent's Cel Shading/Transparent"
{
	Properties
	{
		_MainTex("MainTex", 2D) = "white" {}
		_Color("Color", Color) = (1,1,1,1)
		_ColorMask("ColorMask", 2D) = "white" {}
		[Toggle(_SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A)]_AlbedoAlphaMode("Albedo Alpha Mode", Float) = 0.0
		_Shadow("Shadow Mask Power", Range(0, 1)) = 0.5
		_ShadowLift("Shadow Offset", Range(-1, 1)) = 0.0
		_IndirectLightingBoost("Indirect Lighting Boost", Range(0, 1)) = 0.0
		[Enum(ShadowMaskType)] _ShadowMaskType ("Shadow Mask Type", Float) = 0.0
		_ShadowMask("ShadowMask", 2D) = "white" {}
		_ShadowMaskColor("ShadowMask Color", Color) = (1,1,1,1)
		_Ramp ("Lighting Ramp", 2D) = "white" {}
		_outline_width("outline_width", Float) = 0.1
		_outline_color("outline_color", Color) = (0.5,0.5,0.5,1)
		_outline_tint("outline_tint", Range(0, 1)) = 0.5
		_EmissionMap("Emission Map", 2D) = "white" {}
		[HDR]_EmissionColor("Emission Color", Color) = (0,0,0,1)
		[HDR]_CustomFresnelColor("Emissive Fresnel Color", Color) = (0,0,0,1)
		_SpecGlossMap ("Specular Map", 2D) = "black" {}
		_SpecularDetailMask ("Specular Detail Mask", 2D) = "white" {}
		_SpecularDetailStrength ("Specular Detail Strength", Range(0, 1)) = 1.0
		[Toggle(_)]_UseEnergyConservation ("Energy Conservation", Float) = 0.0
		_Smoothness ("Smoothness", Range(0, 1)) = 1
		_Anisotropy("Anisotropy", Range(-1,1)) = 0.8
		[Toggle(_)]_UseFresnel ("Use Fresnel", Float) = 0.0
		_FresnelWidth ("Fresnel Strength", Range(0, 20)) = .5
		_FresnelStrength ("Fresnel Softness", Range(0.1, 0.9999)) = 0.5
		[HDR]_FresnelTint("Fresnel Tint", Color) = (1,1,1,1)
		_BumpMap("BumpMap", 2D) = "bump" {}
		[Toggle(_DETAIL)]_UseDetailNormal("Enable Detail Normal Map", Float ) = 0.0
		_DetailNormalMap("Detail Normal Map", 2D) = "bump" {}
		_DetailNormalMapScale("Detail Normal Map Scale", Float) = 1.0
		_Cutoff("Alpha cutoff", Range(0,1)) = 0.5
		[Toggle(_)]_AlphaSharp("Disable Dithering", Float) = 0.0
		[HideInInspector] _OutlineMode("__outline_mode", Float) = 0.0
		[Toggle(_)]_UseMatcap ("Use Matcap", Float) = 0.0
		_AdditiveMatcap("AdditiveMatcapTex", 2D) = "black" {}
		_AdditiveMatcapStrength("Additive Matcap Strength", Range(0, 2)) = 1.0
		_MultiplyMatcap("MultiplyMatcapTex", 2D) = "white" {}
		_MultiplyMatcapStrength("Multiply Matcap Strength", Range(0, 2)) = 1.0
		_MatcapMask("Matcap Mask", 2D) = "white" {}
		[Enum(LightRampType)]_LightRampType ("Light Ramp Type", Float) = 0.0
		[Toggle(_)]_UseMetallic ("Use Metallic", Float) = 0.0
		[Enum(SpecularType)] _SpecularType ("Specular Type", Float) = 0.0
		[Toggle(_SPECULAR_DETAIL)] _UseSpecularDetailMask ("Use Specular Detail Mask", Float) = 0.0
		[Enum(LightingCalculationType)] _LightingCalculationType ("Lighting Calculation Type", Float) = 0.0
		[Toggle(_)]_UseSubsurfaceScattering ("Use Subsurface Scattering", Float) = 0.0
		_ThicknessMap("Thickness Map", 2D) = "black" {}
		[Toggle(_)]_ThicknessMapInvert("Invert Thickness", Float) = 0.0
		_ThicknessMapPower ("Thickness Map Power", Range(0.01, 10)) = 1
		_SSSCol ("Scattering Color", Color) = (1,1,1,1)
		_SSSIntensity ("Scattering Intensity", Range(0, 10)) = 1
		_SSSPow ("Scattering Power", Range(0.01, 10)) = 1
		_SSSDist ("Scattering Distance", Range(0, 10)) = 1
		_SSSAmbient ("Scattering Ambient", Range(0, 1)) = 0
		_LightSkew ("Light Skew", Vector) = (1, 0.1, 1, 0)
		[Toggle(_)]_PixelSampleMode("Sharp Sampling Mode", Float) = 0.0
		[ToggleOff(_SPECULARHIGHLIGHTS_OFF)]_SpecularHighlights ("Specular Highlights", Float) = 1.0
		[ToggleOff(_GLOSSYREFLECTIONS_OFF)]_GlossyReflections ("Glossy Reflections", Float) = 1.0
		_UVSec ("UV Set Secondary", Float) = 0
		[Enum(VertexColourType)]_VertexColourType ("Vertex Colour Type", Float) = 0.0

        // Advanced options.
        [Enum(RenderingMode)] _Mode("Rendering Mode", Float) = 0                                     // "Opaque"
        [Enum(CustomRenderingMode)] _CustomMode("Mode", Float) = 0                                   // "Opaque"
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend("Source Blend", Float) = 1                 // "One"
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend("Destination Blend", Float) = 0            // "Zero"
        [Enum(UnityEngine.Rendering.BlendOp)] _BlendOp("Blend Operation", Float) = 0                 // "Add"
        [Enum(UnityEngine.Rendering.CompareFunction)] _ZTest("Depth Test", Float) = 4                // "LessEqual"
        [Enum(DepthWrite)] _ZWrite("Depth Write", Float) = 1                                         // "On"
        [Enum(UnityEngine.Rendering.ColorWriteMask)] _ColorWriteMask("Color Write Mask", Float) = 15 // "All"
        [Enum(UnityEngine.Rendering.CullMode)] _CullMode("Cull Mode", Float) = 2                     // "Back"
        _RenderQueueOverride("Render Queue Override", Range(-1.0, 5000)) = -1
	}

	SubShader
	{
		Tags
		{
			"Queue"="Transparent+100" "RenderType" = "Transparent" "IgnoreProjector"="True"
		}

		Pass
		{

			Name "FORWARD"
			Tags { "LightMode" = "ForwardBase" }

            Blend[_SrcBlend][_DstBlend]
            BlendOp[_BlendOp]
            ZTest[_ZTest]
            ZWrite[_ZWrite]
            Cull[_CullMode]
            ColorMask[_ColorWriteMask]

			CGPROGRAM

			#define UNITY_PASS_FORWARDBASE

			#pragma shader_feature NO_OUTLINE TINTED_OUTLINE COLORED_OUTLINE
			#pragma shader_feature _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
			#pragma shader_feature _DETAIL
			#pragma shader_feature _SPECULAR_DETAIL
			#pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
			#pragma shader_feature _SPECULARHIGHLIGHTS_OFF
			#pragma shader_feature _GLOSSYREFLECTIONS_OFF

			// When sampling lighting, Unity assume L2 probe sampling will be done
			// in the vertex shader. However, this would be problematic due to 
			// the requirements of cel shading. 
			#define UNITY_SAMPLE_FULL_SH_PER_PIXEL 1
			
			#if defined(UNITY_SHOULD_SAMPLE_SH)
    		#undef UNITY_SHOULD_SAMPLE_SH
    		#define SAMPLE_SH_NONLINEAR
			#endif
			
			#include "SCSS_Core.cginc"

			#pragma vertex vert
			#pragma geometry geom
			#pragma fragment frag

			#pragma multi_compile_fwdbase nolightmap 
			#pragma multi_compile_fog

			#include "SCSS_Forward.cginc"

			ENDCG
		}


		Pass
		{
			Name "FORWARD_DELTA"
			Tags { "LightMode" = "ForwardAdd" }
			Blend [_SrcBlend] One

			CGPROGRAM

			#define UNITY_PASS_FORWARDADD

			#pragma shader_feature NO_OUTLINE TINTED_OUTLINE COLORED_OUTLINE
			#pragma shader_feature _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
			#pragma shader_feature _DETAIL
			#pragma shader_feature _SPECULAR_DETAIL
			#pragma shader_feature _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
			#pragma shader_feature _SPECULARHIGHLIGHTS_OFF
			#pragma shader_feature _GLOSSYREFLECTIONS_OFF

			#include "SCSS_Core.cginc"

			#pragma vertex vert
			#pragma geometry geom
			#pragma fragment frag

			#pragma multi_compile_fwdadd nolightmap 
			#pragma multi_compile_fog

			#include "SCSS_Forward.cginc"

			ENDCG
		}

		Pass
		{
			Name "SHADOW_CASTER" 
			Tags{ "LightMode" = "ShadowCaster" }

            Blend[_SrcBlend][_DstBlend]
            BlendOp[_BlendOp]
            ZTest[_ZTest]
            ZWrite[_ZWrite]
            Cull[_CullMode]
            ColorMask[_ColorWriteMask]

			CGPROGRAM
			#define UNITY_PASS_SHADOWCASTER
			#pragma shader_feature _ _ALPHATEST_ON _ALPHABLEND_ON _ALPHAPREMULTIPLY_ON
			#include "SCSS_Shadows.cginc"
			
			#pragma multi_compile_shadowcaster

			#pragma vertex vertShadowCaster
			#pragma fragment fragShadowCaster
			ENDCG
		}
	}
	FallBack "Diffuse"
	CustomEditor "SilentCelShading.Unity.Inspector"
}