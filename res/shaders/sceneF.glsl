
//GLSL Version
#version 330

//Light Count Constants
const int MAX_LIGHT_POINTS = 5;
const int MAX_SPOT_LIGHTS = 5;

//Ins
in vec2 textureCoordsFrag;  //color passed from vertex shader
in vec3 mvVertexNormal;     //vertex normal vector from vertex shader for lighting calculations (model view space)
in vec3 mvVertexPos;        //vertex position from vertex shader for lighting calculations (model view space)
in vec4 mlightviewVertexPos;
in mat4 modelViewFrag;      //ModelView matrix used for normal maps

//Out
out vec4 fragColor;        //output variable definition

//Attenuation Struct (takes into account distance for lighting)
struct Attenuation {
    float constant;
    float linear;
    float exponent;
};

//Light Point Struct
struct LightPoint { //assumed to be in view coordinates
    vec3 color;
    vec3 position;
    float intensity; //0.0f - 1.0f
    Attenuation attenuation;
};

//Directional Light Struct
struct DirectionalLight {
    vec3 color;
    vec3 direction;
    float intensity;
};

//Spot Light Struct
struct SpotLight {
    LightPoint lightPoint;
    vec3 direction;
    float cutoff;
};

//Fog Struct
struct Fog {
    int activeFog;
    vec3 color;
    float density;
};

/*
    a material is defined by a set of colors (if we don't use texture to color the fragments)
    ambient, diffuse, specular components
    a material is also defined by a flag that controls if it has an associated texture or not, and
    a reflectance index.
*/
//Material Struct
struct Material {
    vec4 ambient;
    vec4 diffuse;
    vec4 specular;
    int hasTexture;
    int hasNormalMap;
    float reflectance;
};

//Uniforms
uniform sampler2D textureSampler;   //use this to define which texture unit/bank of the graphics card we will store the texture in
uniform sampler2D normalMapSampler; //use this to define the texture unit/bank for the normal map texture
uniform sampler2D shadowMap;        //use this to create shadows
uniform vec3 ambientLight;          //a color which will affect every fragment in the same way (ambient light)
uniform float specularPower;        //exponent used in calculation specular light
uniform Material material;          //material characteristics

//Light Object and Fog Uniforms
uniform LightPoint lightPoints[MAX_LIGHT_POINTS];
uniform SpotLight spotLights[MAX_SPOT_LIGHTS];
uniform DirectionalLight directionalLight;
uniform Fog fog;

//Global Variables - use these for the material so that we do not do redundant texture lookups
//if the material uses a texture instead of a color
vec4 ambientC; //ambient color
vec4 diffuseC; //diffuse color
vec4 specularC; //specular color

//Color Setup Function
void setupColors(Material material, vec2 textureCoordinate) {

    //setup global variables according to whether the material has a texture or not
    if (material.hasTexture == 1) { //if texture
        ambientC = texture(textureSampler, textureCoordinate); //set ambient base to texture sampled color
        diffuseC = ambientC; //set diffuse base to texture sampled color
        specularC = ambientC; //set specular base to texture sampled color
    } else { //otherwise, set all the bases to the material's self-defined colors;
        ambientC = material.ambient;
        diffuseC = material.diffuse;
        specularC = material.specular;
    }
}

//Light Color Calculation Function
vec4 calculateLightColor(vec3 lightColor, float lightIntensity, vec3 position, vec3 toLightDirection, vec3 normal) {

    //create diffuse and specular vectors
    vec4 diffuseColor = vec4(0, 0, 0, 0);
    vec4 specularColor = vec4(0, 0, 0, 0);

    //diffuse light
    float diffuseFactor = max(dot(normal, toLightDirection), 0.0);
    diffuseColor = diffuseC * vec4(lightColor, 1.0) * lightIntensity * diffuseFactor;

    //specular light
    vec3 cameraDirection = normalize(-position);
    vec3 fromLightDirection = -toLightDirection;
    vec3 reflectedLight = normalize(reflect(fromLightDirection, normal));
    float specularFactor = max(dot(cameraDirection, reflectedLight), 0.0);
    specularFactor = pow(specularFactor, specularPower);
    specularColor = specularC * lightIntensity * specularFactor * material.reflectance * vec4(lightColor, 1.0);

    //combination of the two
    return (diffuseColor + specularColor);
}

//Light Point Calculation Function
vec4 calculateLightPoint(LightPoint light, vec3 position, vec3 normal) {

    //get base light color
    vec3 lightDirection = light.position - position;
    vec3 toLightDir = normalize(lightDirection);
    vec4 lightColor = calculateLightColor(light.color, light.intensity, position, toLightDir, normal);

    //apply attenuation
    float distance = length(lightDirection);
    float attenuationInv = light.attenuation.constant + light.attenuation.linear * distance + light.attenuation.exponent * distance * distance;
    return lightColor / attenuationInv;
}

//Spot Light Calculation Function
vec4 calculateSpotLight(SpotLight light, vec3 position, vec3 normal) {

    //get vector from light to fragment
    vec3 lightDirection = light.lightPoint.position - position;
    vec3 toLightDirection = normalize(lightDirection);
    vec3 fromLightDirection = -toLightDirection;
    float spotAlfa = dot(fromLightDirection, normalize(light.direction));

    //apply lighting changes if within cone of spot light
    vec4 color = vec4(0, 0, 0, 0);
    if (spotAlfa > light.cutoff) { //check if fragment is within the cone of spotlight
        color = calculateLightPoint(light.lightPoint, position, normal);
        color *= (1.0 - (1.0 - spotAlfa)/(1.0 - light.cutoff));
    }
    return color;
}

//Directional Light Calculation Function
vec4 calculateDirectionLight(DirectionalLight light, vec3 position, vec3 normal) {
    return calculateLightColor(light.color, light.intensity, position, normalize(light.direction), normal);
}

//Fog Calculation Function
vec4 calculateFog(vec3 pos, vec4 color, Fog fog, vec3 ambientLight, DirectionalLight directionalLight) {

    //calculate fog
    vec3 fogColor = fog.color * (ambientLight + directionalLight.color * directionalLight.intensity);
    float distance = length(pos);
    float fogFactor = 1.0 / exp((distance * fog.density) * (distance * fog.density));
    fogFactor = clamp(fogFactor, 0.0, 1.0);

    //calculate final color
    vec3 resultColor = mix(fogColor, color.xyz, fogFactor);
    return vec4(resultColor.xyz, color.w);
}

//Normal Calculation Function
vec3 calcNormal(Material material, vec3 normal, vec2 texCoord, mat4 modelViewMatrix) {
    vec3 newNormal = normal;
    if (material.hasNormalMap == 1) {
        newNormal = texture(normalMapSampler, texCoord).rgb;
        newNormal = normalize(newNormal * 2 - 1);
        newNormal = normalize(modelViewMatrix * vec4(newNormal, 0.0)).xyz;
    }
    return newNormal;
}

//Shadow Calculation Function
float calculateShadow(vec4 position) {
    float shadowFactor = 1.0;
    vec3 projCoords = position.xyz;
    vec2 inc = 1.0 / textureSize(shadowMap, 0);

    //transform from screen coordinates to texture coordinates
    projCoords = projCoords * 0.5 + 0.5;
    float bias = 0.05;
    for (int row = -1; row <= 1; ++row) {
        for (int col = -1; col <= 1; ++col) {
            float texDepth = texture(shadowMap, projCoords.xy + vec2(row, col) * inc).r;
            shadowFactor += projCoords.z - bias > texDepth ? 1.0 : 0.0;
        }
    }

    shadowFactor /= 9.0;
    if (projCoords.z > 1.0) shadowFactor = 1.0;

    return 1 - shadowFactor;
}

//Main Function
void main() {

    //setup color bases
    setupColors(material, textureCoordsFrag); //setup the color bases we will be working with (texture or manually provided?)

    //calculate normal
    vec3 currNormal = calcNormal(material, mvVertexNormal, textureCoordsFrag, modelViewFrag);

    //account for directional light
    vec4 diffuseSpecularComp = calculateDirectionLight(directionalLight, mvVertexPos, currNormal); //calculate diffuse and specular light for sun

    //account for light points
    for (int i = 0; i < MAX_LIGHT_POINTS; i++) {
        if (lightPoints[i].intensity > 0) {
            diffuseSpecularComp += calculateLightPoint(lightPoints[i], mvVertexPos, currNormal);
        }
    }

    //account for spot lights
    for (int i = 0; i < MAX_SPOT_LIGHTS; i++) {
        if (spotLights[i].lightPoint.intensity > 0) {
            diffuseSpecularComp += calculateSpotLight(spotLights[i], mvVertexPos, currNormal);
        }
    }

    //account for ambient light
    float shadow = calculateShadow(mlightviewVertexPos);
    fragColor = clamp(ambientC * vec4(ambientLight, 1) + diffuseSpecularComp * shadow, 0, 1); //add ambient light (unaffected by atten.) and return final fragment color

    //account for fog
    if (fog.activeFog == 1) {
        fragColor = calculateFog(mvVertexPos, fragColor, fog, ambientLight, directionalLight);
    }
}
