// For pass "FORWARD"
float4 frag(VertexOutput i) : COLOR
{
	float4 objPos = mul(unity_ObjectToWorld, float4(0,0,0,1));
	i.normalDir = normalize(i.normalDir);
	float3x3 tangentTransform = float3x3(i.tangentDir, i.bitangentDir, i.normalDir);
	float3 _BumpMap_var = UnpackNormal(tex2D(_BumpMap,TRANSFORM_TEX(i.uv0, _MainTex)));
	float3 normalDirection = normalize(mul(_BumpMap_var.rgb, tangentTransform)); // Perturbed normals
	float4 _MainTex_var = tex2D(_MainTex,TRANSFORM_TEX(i.uv0, _MainTex));

	float4 _EmissionMap_var = tex2D(_EmissionMap,TRANSFORM_TEX(i.uv0, _MainTex));
	float3 emissive = (_EmissionMap_var.rgb*_EmissionColor.rgb);
	float4 _ColorMask_var = tex2D(_ColorMask,TRANSFORM_TEX(i.uv0, _MainTex));
	float4 baseColor = lerp((_MainTex_var.rgba*_Color.rgba),_MainTex_var.rgba,_ColorMask_var.r);
	baseColor *= float4(i.col.rgb, 1); // Could vertex alpha be used, ever? Let's hope not.

	float3 lightDirection = normalize(_WorldSpaceLightPos0.xyz + 0.0000001); // Offset to avoid error in lightless worlds.
	UNITY_LIGHT_ATTENUATION(attenuation, i, i.posWorld.xyz);
	float3 viewDirection = normalize(_WorldSpaceCameraPos.xyz - i.posWorld.xyz);

	#if COLORED_OUTLINE
	if(i.is_outline) 
	{
		baseColor.rgb = i.col.rgb; 
	}
	#endif

	// Todo: Some characters can use dithered transparency,
	// like Miku's sleeves, while others get broken by it. 
	#if defined(_ALPHATEST_ON)
		float mask = saturate(interleaved_gradient(i.pos.xy)); 
		//float mask = (float((9*int(i.pos.x)+5*int(i.pos.y))%11) + 0.5) / 11.0;
		mask = (1-_Cutoff) * (mask + _Cutoff);
		clip (baseColor.a - mask);
	#endif

	// Lighting parameters
	float3 halfDir = Unity_SafeNormalize (lightDirection + viewDirection);
	float3 reflDir = reflect(viewDirection, normalDirection); // Calculate reflection vector
	float NdotL = saturate(dot(lightDirection, normalDirection)); // Calculate NdotL
	float NdotV = saturate(dot(viewDirection,  normalDirection)); // Calculate NdotV
	float LdotH = saturate(dot(lightDirection, halfDir));

	float2 rlPow4 = Pow4(float2(dot(reflDir, lightDirection), 1 - NdotV));  // "use R.L instead of N.H to save couple of instructions"

	// Ambient fresnel	
	float fresnelEffect = 0.0;

	#if defined(_FRESNEL)
		fresnelEffect = rlPow4.y;
		float2 fresStep = .5 + float2(-1, 1) * fwidth(rlPow4.y);
		// Sharper rim lighting for the anime look.
		fresnelEffect *= _FresnelWidth;
		float2 fresStep_var = lerp(float2(0.0, 1.0), fresStep, 1-_FresnelStrength);
		fresnelEffect = smoothstep(fresStep_var.x, fresStep_var.y, fresnelEffect);
		fresnelEffect *= _FresnelTint.rgb * _FresnelTint.a;
	#endif

	// Customisable fresnel for a user-defined glow
	emissive += _CustomFresnelColor.xyz * (pow(rlPow4.y, rcp(_CustomFresnelColor.w+0.0001)));

	float3 lightmap = float4(1.0,1.0,1.0,1.0);
	#ifdef LIGHTMAP_ON
		lightmap = DecodeLightmap(UNITY_SAMPLE_TEX2D(unity_Lightmap, i.uv1 * unity_LightmapST.xy + unity_LightmapST.zw));
	#endif

	// Seperate energy conserved and original value for later.
	float3 diffuseColor = baseColor.xyz;

	#if defined(USE_SPECULAR)
		// Specular, high quality (but with probably decent performance)
		float4 _SpecularMap_var = tex2D(_SpecularMap,TRANSFORM_TEX(i.uv0, _MainTex));

		#if defined(_SPECULAR_DETAIL)
		float4 _SpecularDetailMask_var = tex2D(_SpecularDetailMask,TRANSFORM_TEX(i.uv0, _SpecularDetailMask));
		_SpecularMap_var *= saturate(_SpecularDetailMask_var + 1-_SpecularDetailStrength);
		#endif

		// Todo: Add smoothness in diffuse alpha support
		float3 specColor = _SpecularMap_var.rgb;
		float _Smoothness_var = _Smoothness * _SpecularMap_var.w;

		// Because specular behaves poorly on backfaces, disable specular on outlines. 
		if(i.is_outline) 
		{
			specColor = 0;
			_Smoothness_var = 0;
		}

		// Perceptual roughness transformation...
		float roughness = SmoothnessToRoughness(_Smoothness_var);
		
		// Specular energy converservation. From EnergyConservationBetweenDiffuseAndSpecular in UnityStandardUtils.cginc
		half oneMinusReflectivity = 1 - max3(specColor);

		// oneMinusRoughness + (1 - oneMinusReflectivity)
		float grazingTerm = saturate(1-roughness + (1-oneMinusReflectivity));

		#if defined(_METALLIC)
			specColor *= diffuseColor.rgb; // For metallic maps
		#endif
		#if defined(_ENERGY_CONSERVE)
			diffuseColor.xyz = diffuseColor.xyz * (oneMinusReflectivity); 
			// Unity's boost to diffuse power to accomodate rougher metals.
			diffuseColor.xyz += specColor.xyz * (1 - _Smoothness_var) * 0.5;
		#endif
	#endif

	float grayscalelightcolor 	 = dot(_LightColor0.rgb, grayscale_vector);
	float bottomIndirectLighting = grayscaleSH9(float3(0.0, -1.0, 0.0));
	float topIndirectLighting 	 = grayscaleSH9(float3(0.0, 1.0, 0.0));

	float grayscaleDirectLighting = NdotL * grayscalelightcolor * attenuation + grayscaleSH9(normalDirection);

	float lightDifference = topIndirectLighting + grayscalelightcolor - bottomIndirectLighting;
	float remappedLight   = (grayscaleDirectLighting - bottomIndirectLighting) / lightDifference;

	// Todo: Only if shadow mask is selected?
	#if 1
	float4 shadowMask = tex2D(_ShadowMask,TRANSFORM_TEX(i.uv0, _MainTex));
	#endif
	// Shadow mask handling
	#if 1
	// RGB will boost shadow range. Raising _Shadow reduces its influence.
	// Alpha will boost light range. Raising _Shadow reduces its influence.
	remappedLight = min(remappedLight, (remappedLight * shadowMask)+_Shadow);
	remappedLight = max(remappedLight, (remappedLight * (1+1-shadowMask.w)));
	remappedLight = saturate(remappedLight);
	#endif
	#if 0
	remappedLight = lerp(
		remappedLight * shadowMask.xyz * (1-shadowMask.w+1),
		remappedLight,
		_Shadow
		);
	#endif

	// Shadow appearance setting
	remappedLight = saturate(_ShadowLift + remappedLight * (1-_ShadowLift));

	// Remove light influence from outlines. 
	//remappedLight = i.is_outline? 0 : remappedLight;

	float3 lightContribution = 1;
	#if 1
		// Apply lightramp to lighting
		lightContribution = tex2D(_Ramp, saturate(
			#if _LIGHTRAMP_VERTICAL
			float2( 0.0, remappedLight)
			#else
			float2( remappedLight, 0.0)
			#endif
			) );
	#else
		// Lighting without lightramp
		#if 1
			// This produces more instructions, but also an antialiased edge. 
			float shadeWidth = max(fwidth(remappedLight), 0.01);

			// Create two variables storing values similar to 0.49 and 0.51 that the fractional part
			// of the lighting is squeezed into. Then add the non-fractional part to the result.
			// Using fwidth (which should be cheap), we can come up with a gradient
			// about the size of 2 pixels in screen space at minimum.
			// Note: This might be slower than just sampling a light ramp,
			// but popular thought states math > textures for modern GPUs.

			float2 shadeOffset = 0.50 + float2(-shadeWidth, shadeWidth); 
			lightContribution = smoothstep(shadeOffset.x, shadeOffset.y, frac(remappedLight)); 
			lightContribution += floor(remappedLight);
		#else
			// Cubed's original
			//lightContribution = saturate((1.0 - _Shadow) + floor(saturate(remappedLight) * 2.0)); 
			lightContribution = saturate(floor(saturate(remappedLight) * 2.0)); 
		#endif
	#endif

	// Apply indirect lighting shift.
	lightContribution = lightContribution*(1-_IndirectLightingBoost)+_IndirectLightingBoost;

	#if defined(_MATCAP)
		// Based on Masataka SUMI's implementation
	    half3 worldUp = float3(0, 1, 0);
	    half3 worldViewUp = normalize(worldUp - viewDirection * dot(viewDirection, worldUp));
	    half3 worldViewRight = normalize(cross(viewDirection, worldViewUp));
	    half2 matcapUV = half2(dot(worldViewRight, normalDirection), dot(worldViewUp, normalDirection)) * 0.5 + 0.5;
	
		float3 AdditiveMatcap = tex2D(_AdditiveMatcap, matcapUV);
		float3 MultiplyMatcap = tex2D(_MultiplyMatcap, matcapUV);
		float4 _MatcapMask_var = tex2D(_MatcapMask,TRANSFORM_TEX(i.uv0, _MainTex));
		diffuseColor.xyz = lerp(diffuseColor.xyz, diffuseColor.xyz*MultiplyMatcap, _MultiplyMatcapStrength * _MatcapMask_var.w);
		diffuseColor.xyz += grayscaleDirectLighting*AdditiveMatcap*_AdditiveMatcapStrength*_MatcapMask_var.g;
	#endif
	//float horizon = min(1.0 + dot(reflDir, normalDirection), 1.0);

	#if defined(_LIGHTINGTYPE_CUBED)
		float3 indirectLighting = ((ShadeSH9_mod(half4(0.0, -1.0, 0.0, 1.0)))); 
		float3 directLighting   = ((ShadeSH9_mod(half4(0.0,  1.0, 0.0, 1.0)) + _LightColor0.rgb)) ;
	#endif
	#if defined(_LIGHTINGTYPE_ARKTOON)
		float3 directLighting   = ((GetSHLength() + _LightColor0.rgb)) ;
		float3 indirectLighting = ((ShadeSH9_mod(half4(0.0,  0.0, 0.0, 1.0)))); 
	#endif

	// Physically based specular
	#if defined(USE_SPECULAR) || defined(_LIGHTINGTYPE_STANDARD)
		half nh = saturate(dot(normalDirection, halfDir));
		#if defined(_SPECULAR_GGX)
			half V = SmithJointGGXVisibilityTerm (NdotL, NdotV, roughness);
		    half D = GGXTerm (nh, roughness);
	    #endif
		#if defined(_SPECULAR_CHARLIE)
			half V = V_Neubelt (NdotV, NdotL);
		    half D = D_Charlie (roughness, nh);
	    #endif
	    #if defined(_SPECULAR_GGX_ANISO)
		    float anisotropy = _Anisotropy;
		    float at = max(roughness * (1.0 + anisotropy), 0.001);
		    float ab = max(roughness * (1.0 - anisotropy), 0.001);
			half V = SmithJointGGXVisibilityTerm (NdotL, NdotV, roughness);
		    half D = D_GGX_Anisotropic(nh, halfDir, i.tangentDir, i.bitangentDir, at, ab);
	    #endif

	    #if defined(_LIGHTINGTYPE_STANDARD) & !defined(USE_SPECULAR)
	    // Awkward
	    	half V = 0; half D = 0; half roughness = 0; half specColor = 0; half grazingTerm = 0;
	    #endif

	    half specularTerm = V*D * UNITY_PI; // Torrance-Sparrow model, Fresnel is applied later
	    specularTerm = max(0, specularTerm * NdotL);

		half surfaceReduction = 1.0 / (roughness*roughness + 1);

		UnityGI gi =  GetUnityGI(_LightColor0.rgb, lightDirection, 
		normalDirection, viewDirection, reflDir, attenuation, roughness, i.posWorld.xyz);

		//lightContribution = DisneyDiffuse(NdotV, NdotL, LdotH, roughness) * NdotL;

		#if defined(_LIGHTINGTYPE_STANDARD)
			float3 directContribution = diffuseColor * (gi.indirect.diffuse.rgb + _LightColor0.rgb * lightContribution);
		#else
			float3 directContribution = diffuseColor * 
			lerp(indirectLighting, directLighting, lightContribution);
		#endif

		directContribution += i.vertexLight;

		#if defined(_FRESNEL)
			directContribution *= 1+fresnelEffect;
		#endif

		float3 finalColor = emissive + directContribution +
		specularTerm * gi.light.color * FresnelTerm(specColor, LdotH) +
		surfaceReduction * gi.indirect.specular.rgb * FresnelLerp(specColor, grazingTerm, NdotV);
	#else
		float3 directContribution = diffuseColor * 
		lerp(indirectLighting, directLighting, lightContribution);

		directContribution += i.vertexLight;

		#if defined(_FRESNEL)
			directContribution *= 1+fresnelEffect;
		#endif

		float3 finalColor = directContribution + emissive;
	#endif

	fixed4 finalRGBA = fixed4(finalColor * lightmap, baseColor.a);
	UNITY_APPLY_FOG(i.fogCoord, finalRGBA);
	return finalRGBA;
}