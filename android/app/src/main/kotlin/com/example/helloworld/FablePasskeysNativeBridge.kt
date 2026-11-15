package com.example.helloworld

import android.app.Activity
import android.os.CancellationSignal
import androidx.core.content.ContextCompat
import androidx.credentials.CreateCredentialResponse
import androidx.credentials.CreatePublicKeyCredentialRequest
import androidx.credentials.CreatePublicKeyCredentialResponse
import androidx.credentials.CredentialManager
import androidx.credentials.CredentialManagerCallback
import androidx.credentials.GetCredentialRequest
import androidx.credentials.GetCredentialResponse
import androidx.credentials.GetPublicKeyCredentialOption
import androidx.credentials.PublicKeyCredential
import androidx.credentials.exceptions.CreateCredentialException
import androidx.credentials.exceptions.GetCredentialException
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * Uses Android Credential Manager, not Dart crypto, to create and assert real
 * platform passkeys. OS enforces Digital Asset Links for the signed APK + RP.
 * Backend independently verifies WebAuthn challenge, RP origin and signature.
 */
internal class FablePasskeysNativeBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val channel=MethodChannel(messenger,"fable/passkeys_native_v1")
    private val manager=CredentialManager.create(activity)
    private var pending:MethodChannel.Result?=null
    private var cancellation:CancellationSignal?=null
    private var disposed=false

    init {
        channel.setMethodCallHandler { call,result ->
            if(disposed){result.error("PASSKEY_UNAVAILABLE","Passkeys bridge disposed",null);return@setMethodCallHandler}
            if(pending!=null){result.error("PASSKEY_BUSY","Another OS credential request is pending",null);return@setMethodCallHandler}
            if(call.method!="register"&&call.method!="authenticate"){result.notImplemented();return@setMethodCallHandler}
            @Suppress("UNCHECKED_CAST")
            val options=call.argument<Map<String,Any?>>("options")
            if(options==null){result.error("PASSKEY_OPTIONS_INVALID","Missing server options",null);return@setMethodCallHandler}
            val json=try{JSONObject(options)}catch(_:Exception){
                result.error("PASSKEY_OPTIONS_INVALID","Malformed server options",null);return@setMethodCallHandler
            }
            val challenge=json.optString("challenge","")
            val rp=if(call.method=="register")json.optJSONObject("rp")?.optString("id","")
                   else json.optString("rpId","")
            if(json.toString().length>131072||
                !Regex("^[A-Za-z0-9_-]{16,1024}$").matches(challenge)||
                rp.isNullOrEmpty()||rp.length>253||!rp.contains('.')||
                rp.contains("..")||!rp.all{it.isLetterOrDigit()||it=='.'||it=='-'}){
                result.error("PASSKEY_OPTIONS_INVALID","Untrusted WebAuthn challenge or relying party",null)
                return@setMethodCallHandler
            }
            if(call.method=="register"){
                val user=json.optJSONObject("user")
                val userId=user?.optString("id","").orEmpty()
                val name=user?.optString("name","").orEmpty()
                if(!Regex("^[A-Za-z0-9_-]{8,1024}$").matches(userId)||
                    name.isEmpty()||name.length>191){
                    result.error("PASSKEY_OPTIONS_INVALID","Malformed WebAuthn registration user",null)
                    return@setMethodCallHandler
                }
            }
            val signal=CancellationSignal()
            pending=result
            cancellation=signal
            try{
                if(call.method=="register"){
                    val request=CreatePublicKeyCredentialRequest(json.toString())
                    manager.createCredentialAsync(activity,request,signal,
                        ContextCompat.getMainExecutor(activity),
                        object:CredentialManagerCallback<CreateCredentialResponse,CreateCredentialException>{
                            override fun onResult(result:CreateCredentialResponse){
                                if(result !is CreatePublicKeyCredentialResponse){
                                    fail("PASSKEY_INVALID","Unexpected credential type");return
                                }
                                succeed(result.registrationResponseJson)
                            }
                            override fun onError(e:CreateCredentialException){
                                fail(if(e.javaClass.simpleName.contains("Cancellation"))
                                    "USER_CANCELLED" else "PASSKEY_UNAVAILABLE",
                                    "Native credential registration failed")
                            }
                        })
                }else{
                    val request=GetCredentialRequest(
                        listOf(GetPublicKeyCredentialOption(json.toString())))
                    manager.getCredentialAsync(activity,request,signal,
                        ContextCompat.getMainExecutor(activity),
                        object:CredentialManagerCallback<GetCredentialResponse,GetCredentialException>{
                            override fun onResult(result:GetCredentialResponse){
                                val credential=result.credential
                                if(credential !is PublicKeyCredential){
                                    fail("PASSKEY_INVALID","Unexpected credential type");return
                                }
                                succeed(credential.authenticationResponseJson)
                            }
                            override fun onError(e:GetCredentialException){
                                fail(if(e.javaClass.simpleName.contains("Cancellation"))
                                    "USER_CANCELLED" else "PASSKEY_UNAVAILABLE",
                                    "Native credential sign-in failed")
                            }
                        })
                }
            }catch(_:Exception){
                fail("PASSKEY_UNAVAILABLE","Unable to start native credential request")
            }
        }
    }

    private fun succeed(json:String){
        val callback=pending?:return
        pending=null
        cancellation=null
        if(disposed)return
        try{
            val value=JSONObject(json)
            if(json.length>131072||value.optString("id","").isEmpty()||
                value.optJSONObject("response")==null){
                callback.error("PASSKEY_INVALID","Malformed native WebAuthn result",null)
            }else callback.success(json)
        }catch(_:Exception){
            callback.error("PASSKEY_INVALID","Malformed native WebAuthn JSON",null)
        }
    }

    private fun fail(code:String,message:String){
        val callback=pending?:return
        pending=null
        cancellation=null
        if(!disposed)callback.error(code,message,null)
    }

    fun dispose(){
        disposed=true
        cancellation?.cancel()
        cancellation=null
        pending?.error("PASSKEY_UNAVAILABLE","Credential request interrupted",null)
        pending=null
        channel.setMethodCallHandler(null)
    }
}
