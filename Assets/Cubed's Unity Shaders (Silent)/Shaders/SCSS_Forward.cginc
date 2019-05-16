float4 frag(VertexOutput i, uint facing : SV_IsFrontFace) : SV_Target
{
	float4 objPos = mul(unity_ObjectToWorld, float4(0,0,0,1));
	i.normalDir = normalize(i.normalDir);
	float3x3 tangentTransform = float3x3(i.tangentDir, i.bitangentDir, i.normalDir);

	float2 mainUVs = _PixelSampleMode? sharpSample(_MainTex_TexelSize.zw, i.uv0) : i.uv0;

	// Colour and detail mask. Green is colour tint mask, while alpha is normal detail mask.
	float4 _ColorMask_var = tex2D(_ColorMask,TRANSFORM_TEX(i.uv0, _MainTex));
	float3 _BumpMap_var = NormalInTangentSpace(i.uv0, _ColorMask_var.a);

	float3 normalDirection = normalize(mul(_BumpMap_var.rgb, tangentTransform)); // Perturbed normals

	facing = inMirror()? !facing : facing;
	normalDirection.z *= facing? 1 : -1; // Correct backfaces
	if (i.is_outline && !facing) discard;

	float4 _MainTex_var = tex2D(_MainTex,TRANSFORM_TEX(mainUVs, _MainTex));

	float3 emissive = 0; // Not used in add pass.
	#if defined(UNITY_PASS_FORWARDBASE)
	float4 _EmissionMap_var = tex2D(_EmissionMap,TRANSFORM_TEX(i.uv0, _MainTex));
	emissive += (_EmissionMap_var.rgb*_EmissionColor.rgb);
	#endif

	float3 diffuseColor = _MainTex_var.rgb * LerpWhiteTo(_Color.rgb, _ColorMask_var.g);
	float alpha = _MainTex_var.a * _Color.a;

	diffuseColor *= i.color.rgb; // Could vertex alpha be used, ever? Let's hope not.

	float3 lightDirection = Unity_SafeNormalize(_WorldSpaceLightPos0.xyz); 
	UNITY_LIGHT_ATTENUATION(attenuation, i, i.posWorld.xyz);
	float3 viewDirection = normalize(_WorldSpaceCameraPos.xyz - i.posWorld.xyz);

	#if COLORED_OUTLINE
	if(i.is_outline) 
	{
		diffuseColor = i.color.rgb; 
	}
	#endif

	// Todo: Some characters can use dithered transparency,
	// like Miku's sleeves, while others get broken by it. 
	#if defined(_ALPHATEST_ON)
		if (_AlphaSharp  == 0) {
			float mask = (T(intensity(i.pos.xy + _SinTime.x%4)));
			alpha *= alpha;
			alpha = saturate(alpha + alpha * mask); 
			clip (alpha - _Cutoff);
		}
		if (_AlphaSharp  == 1) {
			alpha = ((alpha - _Cutoff) / max(fwidth(alpha), 0.0001) + 0.5);
			clip (alpha);
		}
	#endif

	#if !(defined(_ALPHATEST_ON) || defined(_ALPHABLEND_ON) || defined(_ALPHAPREMULTIPLY_ON))
		alpha = 1.0;
	#endif

	// Lighting parameters
	float3 halfDir = Unity_SafeNormalize (lightDirection + viewDirection);
	float3 reflDir = reflect(-viewDirection, normalDirection); // Calculate reflection vector
	float NdotL = saturate(dot(lightDirection, normalDirection)); // Calculate NdotL
	float NdotV = saturate(dot(viewDirection,  normalDirection)); // Calculate NdotV
	float LdotH = saturate(dot(lightDirection, halfDir));

	float2 rlPow4 = Pow4(float2(dot(reflDir, lightDirection), 1 - NdotV));  // "use R.L instead of N.H to save couple of instructions"

	// Ambient fresnel	
	float3 fresnelEffect = 0.0;

	if (_UseFresnel == 1)
	{
		fresnelEffect = rlPow4.y;
		float2 fresStep = .5 + float2(-1, 1) * fwidth(rlPow4.y);
		// Sharper rim lighting for the anime look.
		fresnelEffect *= _FresnelWidth;
		float2 fresStep_var = lerp(float2(0.0, 1.0), fresStep, 1-_FresnelStrength);
		fresnelEffect = smoothstep(fresStep_var.x, fresStep_var.y, fresnelEffect);
		fresnelEffect *= _FresnelTint.rgb * _FresnelTint.a;
		fresnelEffect *= 1-i.is_outline;
	}

	// Customisable fresnel for a user-defined glow
	#if defined(UNITY_PASS_FORWARDBASE)
	emissive += _CustomFresnelColor.xyz * (pow(rlPow4.y, rcp(_CustomFresnelColor.w+0.0001)));
	#endif

	float3 lightmap = float4(1.0,1.0,1.0,1.0);
	#if defined(LIGHTMAP_ON)
		lightmap = DecodeLightmap(UNITY_SAMPLE_TEX2D(unity_Lightmap, i.uv1 * unity_LightmapST.xy + unity_LightmapST.zw));
	#endif

	// Shadowmask/AO handling
	float4 _ShadowMask_var = tex2D(_ShadowMask,TRANSFORM_TEX(i.uv0, _MainTex));

	if (_ShadowMaskType == 0) 
	{
		// RGB will boost shadow range. Raising _Shadow reduces its influence.
		// Alpha will boost light range. Raising _Shadow reduces its influence.
		_ShadowMask_var = float4(_ShadowMaskColor.rgb*(1-_ShadowMask_var.w), _ShadowMaskColor.a*_ShadowMask_var.r);
	}
	if (_ShadowMaskType == 1) 
	{
		_ShadowMask_var = _ShadowMask_var * _ShadowMaskColor;
	}

	_ShadowMask_var.rgb = saturate(_ShadowMask_var.rgb + _IndirectLightingBoost);

	float perceptualRoughness = 1; float3 specColor = 0; half grazingTerm = 0; 

	// Specular, high quality (but with probably decent performance)
	if (_SpecularType != 0 )
	{
		float4 _SpecularMap_var = tex2D(_SpecularMap,TRANSFORM_TEX(i.uv0, _MainTex));

		#if defined(_SPECULAR_DETAIL)
		float4 _SpecularDetailMask_var = tex2D(_SpecularDetailMask,TRANSFORM_TEX(i.uv0, _SpecularDetailMask));
		_SpecularMap_var *= saturate(_SpecularDetailMask_var + 1-_SpecularDetailStrength);
		#endif

		// Todo: Add smoothness in diffuse alpha support
		specColor = _SpecularMap_var.rgb;
		float _Smoothness_var = _Smoothness * _SpecularMap_var.w;

		// Because specular behaves poorly on backfaces, disable specular on outlines. 
		if(i.is_outline) 
		{
			specColor = 0;
			_Smoothness_var = 0;
		}

		// Perceptual roughness transformation...
		perceptualRoughness = SmoothnessToPerceptualRoughness(_Smoothness_var);

		// Specular energy converservation. From EnergyConservationBetweenDiffuseAndSpecular in UnityStandardUtils.cginc
		half oneMinusReflectivity = 1 - SpecularStrength(specColor); 

		if (_UseMetallic == 1)
		{
			// From DiffuseAndSpecularFromMetallic
			oneMinusReflectivity = OneMinusReflectivityFromMetallic(specColor);
			specColor = lerp (unity_ColorSpaceDielectricSpec.rgb, diffuseColor, specColor);
		}

		// oneMinusRoughness + (1 - oneMinusReflectivity)
		grazingTerm = saturate(_Smoothness_var + (1-oneMinusReflectivity));

		if (_UseEnergyConservation == 1)
		{
			diffuseColor.xyz = diffuseColor.xyz * (oneMinusReflectivity); 
			// Unity's boost to diffuse power to accomodate rougher metals.
			// Note: It looks like 2017 doesn't do this anymore... 
			// But it looks nice, so I've left it in. Maybe it'll be an option later.
			//diffuseColor.xyz += specColor.xyz * (1 - _Smoothness_var) * 0.5;
		}

	if (_UseEnergyConservation == 1)
	{
		_ShadowMask_var.xyz = _ShadowMask_var.xyz * (oneMinusReflectivity); 
	}
	}

	// Lighting handling

	#if defined(UNITY_PASS_FORWARDBASE)
	// Clamp attenuation by N.L to avoid weird light wrapping effect
	// Though it looks a bit like SSS it also looks really odd in some lighting conditions.
	float directAttenuation = saturate(min(attenuation,dot(normalDirection, lightDirection)+.5));
	#endif

	#if defined(UNITY_PASS_FORWARDBASE)
	    // Derive the dominant light direction from light probes and directional light.
		float ambientProbeIntensity = (unity_SHAr.w + unity_SHAg.w + unity_SHAb.w);
		float3 remappedLightDirection = 
			Unity_SafeNormalize((unity_SHAr.xyz + unity_SHAg.xyz + unity_SHAb.xyz) * _LightSkew.xyz
			+ lightDirection * _LightColor0.w * directAttenuation);

	    #if !defined(DIRECTIONAL) && !defined(POINT) && !defined(SPOT)
	    	attenuation, directAttenuation = 1;
		#endif

		// Attenuation contains the shadow buffer. This makes shadows 0, which means a strict 
		// multiply by attenuation will mean they always use the indirect light colour, even
		// if an area has probe lighting that should override them. 
		// To counter this, attenuation is remapped so that, in areas where probe light exceeds
		// direct light, attenuation is nullified. 
		float remappedAttenuation = saturate((ambientProbeIntensity / _LightColor0.w)+directAttenuation);
		float remappedLight = dot(remappedLightDirection,normalDirection);
		remappedLight *= DisneyDiffuse(NdotV, saturate(remappedLight), LdotH, perceptualRoughness);
		remappedLight *= 0.5 + 0.5;
		remappedLight *= remappedAttenuation;
	#endif

	#if defined(UNITY_PASS_FORWARDADD)
		float ambientProbeIntensity = 0; // Not used
		float remappedAttenuation = 0; // Not used
		float remappedLight = dot(normalize(_WorldSpaceLightPos0.xyz - i.posWorld.xyz),normalDirection)
			* DisneyDiffuse(NdotV, NdotL, LdotH, perceptualRoughness);
	#endif
	remappedLight = saturate(remappedLight);

	// Shadow appearance setting
	remappedLight *= (1 - _Shadow) * _ShadowMask_var.w + _Shadow;
	remappedLight = _ShadowLift + remappedLight * (1-_ShadowLift);

	// Apply lightramp to lighting
	float3 lightContribution = sampleRampWithOptions(remappedLight);
	//lightContribution = lerp(lightening, 1.0, remappedLight);
	lightContribution += (1 - lightContribution) * _ShadowMask_var.rgb
	 * saturate((1+ambientProbeIntensity)/_LightColor0.w);

	remappedAttenuation = max(remappedAttenuation, dot(lightContribution, 1.0/3.0));

	// Matcap handling
	if (_UseMatcap == 1) 
	{
		// Based on Masataka SUMI's implementation
	    half3 worldUp = float3(0, 1, 0);
	    half3 worldViewUp = normalize(worldUp - viewDirection * dot(viewDirection, worldUp));
	    half3 worldViewRight = normalize(cross(viewDirection, worldViewUp));
	    half2 matcapUV = half2(dot(worldViewRight, normalDirection), dot(worldViewUp, normalDirection)) * 0.5 + 0.5;
	
		float3 AdditiveMatcap = tex2D(_AdditiveMatcap, matcapUV);
		float3 MultiplyMatcap = tex2D(_MultiplyMatcap, matcapUV);
		float4 _MatcapMask_var = tex2D(_MatcapMask,TRANSFORM_TEX(i.uv0, _MainTex));
		diffuseColor.xyz = lerp(diffuseColor.xyz, diffuseColor.xyz*MultiplyMatcap, _MultiplyMatcapStrength * _MatcapMask_var.w);
		diffuseColor.xyz += 
			// Additive's power is defined by ambient lighting. 
			#if defined(UNITY_PASS_FORWARDBASE)
			(BetterSH9(half4(0.0,  0.0, 0.0, 1.0))+_LightColor0)
			#endif
			#if defined(UNITY_PASS_FORWARDADD)
			(_LightColor0)
			#endif
			*AdditiveMatcap*_AdditiveMatcapStrength*_MatcapMask_var.g;
			
	}
	//float horizon = min(1.0 + dot(reflDir, normalDirection), 1.0);

	// If we're in the delta pass, then ambient light is always black, because the delta
	// pass is added on top, and vertex lights don't need to be added.
	float3 directLighting = 0.0;
	float3 indirectLighting = 0.0;

	#if defined(UNITY_PASS_FORWARDBASE)
		if (_LightingCalculationType == 0)
		{
			directLighting   = GetSHLength() + _LightColor0.rgb * remappedAttenuation;
			indirectLighting = BetterSH9(half4(0.0, 0.0, 0.0, 1.0)); 
		}
		if (_LightingCalculationType == 2)
		{
			directLighting   = BetterSH9(half4(0.0,  1.0, 0.0, 1.0)) + _LightColor0.rgb * remappedAttenuation;
			indirectLighting = BetterSH9(half4(0.0, -1.0, 0.0, 1.0)); 
		}
	#endif

	#if defined(UNITY_PASS_FORWARDADD)
		directLighting = _LightColor0;
		indirectLighting = 0.0;
	#endif

	float3 vertexContribution = 0;
	#if defined(UNITY_PASS_FORWARDBASE)
		// Vertex lighting based on Shade4PointLights
		float4 vertexAttenuation = i.vertexLight;
		vertexAttenuation *= (1 - _Shadow) * _ShadowMask_var.w + _Shadow;
		vertexAttenuation = max(vertexAttenuation, (vertexAttenuation * (1+1-Luminance(_ShadowMask_var.rgb))));
		vertexAttenuation = saturate(vertexAttenuation);

	    vertexContribution += unity_LightColor[0] * sampleRampWithOptions(vertexAttenuation.x) * vertexAttenuation.x;
	    vertexContribution += unity_LightColor[1] * sampleRampWithOptions(vertexAttenuation.y) * vertexAttenuation.y;
	    vertexContribution += unity_LightColor[2] * sampleRampWithOptions(vertexAttenuation.z) * vertexAttenuation.z;
	    vertexContribution += unity_LightColor[3] * sampleRampWithOptions(vertexAttenuation.w) * vertexAttenuation.w;
	#endif

	// Physically based specular
	float3 finalColor = 0;
	UnityGI gi = (UnityGI)0;
	if ((_SpecularType != 0 ) || (_LightingCalculationType == 1))
	{
		half nh = saturate(dot(normalDirection, halfDir));
	    half V = 0; half D = 0; float3 shiftedTangent = 0;
	    //float roughness = PerceptualRoughnessToRoughness(perceptualRoughness);
	    float roughness = (perceptualRoughness);

		// Valve's geometic specular AA (to reduce shimmering edges)
    	float3 vNormalWsDdx = ddx(i.normalDir.xyz);
    	float3 vNormalWsDdy = ddy(i.normalDir.xyz);
    	float flGeometricRoughnessFactor = pow(saturate(max(dot(vNormalWsDdx.xyz, vNormalWsDdx.xyz), dot(vNormalWsDdy.xyz, vNormalWsDdy.xyz))), 0.333);
    	roughness = min(roughness, 1.0 - flGeometricRoughnessFactor); // Ensure we don't double-count roughness if normal map encodes geometric roughness
    	
		// "GGX with roughness to 0 would mean no specular at all, using max(roughness, 0.002) here to match HDrenderloop roughness remapping."
		// This also fixes issues with the other specular types.
		roughness = max(roughness, 0.002);

    	[call] switch(_SpecularType)
		{
		case 1: // GGX
			V = SmithJointGGXVisibilityTerm (NdotL, NdotV, roughness);
		    D = GGXTerm (nh, roughness);
		    break;

		case 2: // Charlie (cloth)
			V = V_Neubelt (NdotV, NdotL);
		    D = D_Charlie (roughness, nh);
		    break;

		case 3: // GGX anisotropic
		    float anisotropy = _Anisotropy;
		    float at = max(roughness * (1.0 + anisotropy), 0.001);
		    float ab = max(roughness * (1.0 - anisotropy), 0.001);

			#if 0
		    float TdotL = dot(i.tangentDir, lightDirection);
		    float BdotL = dot(i.bitangentDir, lightDirection);
		    float TdotV = dot(i.tangentDir, viewDirection);
		    float BdotV = dot(i.bitangentDir, lightDirection);

		    // Accurate but probably expensive
			float V = V_SmithGGXCorrelated_Anisotropic (at, ab, TdotV, BdotV, TdotL, BdotL, NdotV, NdotL);
			#else
			V = SmithJointGGXVisibilityTerm (NdotL, NdotV, roughness);
			#endif
			// Temporary
			shiftedTangent = ShiftTangent(i.tangentDir, normalDirection, roughness);
		    D = D_GGX_Anisotropic(nh, halfDir, shiftedTangent, i.bitangentDir, at, ab);
		    break;

		case 4: // Strand
			V = SmithJointGGXVisibilityTerm (NdotL, NdotV, roughness);
			// Temporary
			shiftedTangent = ShiftTangent(i.tangentDir, normalDirection, roughness);
		    // exponent, strength
			D = StrandSpecular(shiftedTangent, 
				viewDirection, lightDirection, halfDir, 
				_Anisotropy*100, 1.0 );
			D += StrandSpecular(shiftedTangent, 
				viewDirection, lightDirection, halfDir, 
				_Anisotropy*10, 0.05 );
		    break;
		}

	    half specularTerm = V*D * UNITY_PI; // Torrance-Sparrow model, Fresnel is applied later
	    specularTerm = max(0, specularTerm * NdotL);

	    /* Todo
	    #if defined(_SPECULARHIGHLIGHTS_OFF)
    		specularTerm = 0.0;
		#endif
 		*/

		half surfaceReduction = 1.0 / (roughness*roughness + 1);

    	// To provide true Lambert lighting, we need to be able to kill specular completely.
    	specularTerm *= any(specColor) ? 1.0 : 0.0;

		UnityGI gi =  GetUnityGI(_LightColor0.rgb, lightDirection, 
		normalDirection, viewDirection, reflDir, attenuation, roughness, i.posWorld.xyz);

		float3 directContribution = 0;

		if (_LightingCalculationType == 1) // Standard
		{
			// Match indirect lighting to tonemap
			indirectLighting = gi.indirect.diffuse.rgb 
			#if defined(UNITY_PASS_FORWARDBASE)
			+ BetterSH9(half4(0.0, 0.0, 0.0, 1.0)) * lightContribution
			#endif
			;
			_LightColor0.rgb = max(0.0000001, _LightColor0.rgb);
			directContribution = diffuseColor * 
			(indirectLighting + lightContribution * _LightColor0.rgb);
		} 
		else 
		{
			directContribution = diffuseColor * 
			lerp(indirectLighting, directLighting, lightContribution);
		}

		directContribution += vertexContribution*diffuseColor;
		
		directContribution *= 1+fresnelEffect;

		finalColor = emissive + directContribution +
		specularTerm * (gi.light.color + vertexContribution) * FresnelTerm(specColor, LdotH) +
		surfaceReduction * (gi.indirect.specular.rgb + vertexContribution) * FresnelLerp(specColor, grazingTerm, NdotV);
	}
	else
	{
		float3 directContribution = 0;

		directContribution = diffuseColor * 
		lerp(indirectLighting, directLighting, lightContribution);

		directContribution += vertexContribution*diffuseColor;
		
		directContribution *= 1+fresnelEffect;

		finalColor = directContribution + emissive;
	}

	#if defined(UNITY_PASS_FORWARDADD)
		finalColor *= attenuation;
	#endif

	if (_UseSubsurfaceScattering == 1)
	{
	float3 thicknessMap_var = pow(tex2D(_ThicknessMap, TRANSFORM_TEX(i.uv0, _MainTex)), _ThicknessMapPower);
	finalColor += diffuseColor * getSubsurfaceScatteringLight(_LightColor0, lightDirection, normalDirection, viewDirection,
		attenuation, thicknessMap_var, indirectLighting);
	}

	fixed4 finalRGBA = fixed4(finalColor * lightmap, alpha);
	UNITY_APPLY_FOG(i.fogCoord, finalRGBA);
	return finalRGBA;
}