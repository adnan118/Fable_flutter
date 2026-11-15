import AuthenticationServices
import Flutter
import UIKit

/// RC255: System-owned Passkeys, never a Dart-held private credential.
/// Production signing MUST add webcredentials:<verified RP domain> to the
/// actual app's Associated Domains entitlement; never synthesize the domain.
@available(iOS 15.0, *)
final class FablePasskeysNativeBridge: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

  private let channel: FlutterMethodChannel
  private var pending: FlutterResult?
  private var authorizationController: ASAuthorizationController?
  private var anchor: ASPresentationAnchor?

  init(messenger: FlutterBinaryMessenger) {
    channel=FlutterMethodChannel(
      name:"fable/passkeys_native_v1",binaryMessenger:messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call,result in
      guard let self else {
        result(FlutterError(code:"PASSKEY_UNAVAILABLE",
          message:"Native passkey bridge unavailable",details:nil))
        return
      }
      self.handle(call,result)
    }
  }

  private func urlDecode(_ input:String)->Data? {
    let chars=CharacterSet(charactersIn:
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
    guard input.count>=8 && input.count<=1024 &&
        input.unicodeScalars.allSatisfy({chars.contains($0)}) else{return nil}
    let standard=input.replacingOccurrences(of:"-",with:"+")
      .replacingOccurrences(of:"_",with:"/")
    return Data(base64Encoded:standard+String(
      repeating:"=",count:(4-standard.count%4)%4))
  }

  private func urlEncode(_ value:Data)->String {
    value.base64EncodedString().replacingOccurrences(of:"+",with:"-")
      .replacingOccurrences(of:"/",with:"_")
      .replacingOccurrences(of:"=",with:"")
  }

  private func validRp(_ value:String)->Bool {
    value.count>=4 && value.count<=253 && value.contains(".") &&
      !value.contains("..") &&
      value.unicodeScalars.allSatisfy {
        CharacterSet(charactersIn:
          "abcdefghijklmnopqrstuvwxyz0123456789.-").contains($0)
      }
  }

  private func error(_ code:String,_ message:String){
    finish(FlutterError(code:code,message:message,details:nil))
  }

  private func finish(_ value:Any?){
    let callback=pending
    pending=nil
    authorizationController=nil
    anchor=nil
    callback?(value)
  }

  private func handle(_ call:FlutterMethodCall,_ result:@escaping FlutterResult){
    guard call.method=="register" || call.method=="authenticate" else{
      result(FlutterMethodNotImplemented)
      return
    }
    guard pending==nil else{
      result(FlutterError(code:"PASSKEY_BUSY",
        message:"Another OS passkey request is running",details:nil))
      return
    }
    guard let args=call.arguments as? [String:Any],
          let options=args["options"] as? [String:Any],
          let challengeString=options["challenge"] as? String,
          let challenge=urlDecode(challengeString),
          challenge.count>=16,
          let rpId=(
            call.method=="register"
              ? (options["rp"] as? [String:Any])?["id"]
              : options["rpId"]
          ) as? String,
          validRp(rpId),
          JSONSerialization.isValidJSONObject(options),
          let encodedOptions=try? JSONSerialization.data(withJSONObject:options),
          encodedOptions.count<=131072 else{
      result(FlutterError(code:"PASSKEY_OPTIONS_INVALID",
        message:"Invalid server-issued RP or challenge",details:nil))
      return
    }
    guard let window=UIApplication.shared.connectedScenes
      .compactMap({$0 as? UIWindowScene})
      .flatMap({$0.windows}).first(where:{$0.isKeyWindow}) else{
      result(FlutterError(code:"PASSKEY_UNAVAILABLE",
        message:"No foreground window for system Passkeys",details:nil))
      return
    }
    let provider=ASAuthorizationPlatformPublicKeyCredentialProvider(
      relyingPartyIdentifier:rpId)
    let request:ASAuthorizationRequest
    if call.method=="register" {
      guard let user=options["user"] as? [String:Any],
            let name=user["name"] as? String,
            !name.isEmpty && name.count<=191,
            let userIdString=user["id"] as? String,
            let userId=urlDecode(userIdString),
            userId.count>=8 else{
        result(FlutterError(code:"PASSKEY_OPTIONS_INVALID",
          message:"Invalid server-issued WebAuthn user",details:nil))
        return
      }
      let registration=provider.createCredentialRegistrationRequest(
        challenge:challenge,name:name,userID:userId)
      registration.userVerificationPreference = .required
      if let display=user["displayName"] as? String{
        registration.displayName=String(display.prefix(191))
      }
      request=registration
    }else{
      let assertion=provider.createCredentialAssertionRequest(
        challenge:challenge)
      assertion.userVerificationPreference = .required
      request=assertion
    }
    let controller=ASAuthorizationController(authorizationRequests:[request])
    controller.delegate=self
    controller.presentationContextProvider=self
    self.anchor=window
    self.pending=result
    self.authorizationController=controller
    controller.performRequests()
  }

  func presentationAnchor(for controller:ASAuthorizationController)
      -> ASPresentationAnchor {
    // handle() refuses to start without an active key window.
    return anchor ?? UIWindow()
  }

  func authorizationController(controller:ASAuthorizationController,
      didCompleteWithAuthorization authorization:ASAuthorization){
    var credential:[String:Any]?
    if let registration=authorization.credential as?
        ASAuthorizationPlatformPublicKeyCredentialRegistration {
      if let attestation=registration.rawAttestationObject {
        let id=urlEncode(registration.credentialID)
        credential=[
          "id":id,"rawId":id,"type":"public-key",
          "response":[
            "clientDataJSON":urlEncode(registration.rawClientDataJSON),
            "attestationObject":urlEncode(attestation),
          ],
        ]
      }
    }else if let assertion=authorization.credential as?
        ASAuthorizationPlatformPublicKeyCredentialAssertion {
      let id=urlEncode(assertion.credentialID)
      var response:[String:Any]=[
        "clientDataJSON":urlEncode(assertion.rawClientDataJSON),
        "authenticatorData":urlEncode(assertion.rawAuthenticatorData),
        "signature":urlEncode(assertion.signature),
      ]
      if let userId=assertion.userID {
        response["userHandle"]=urlEncode(userId)
      }
      credential=[
        "id":id,"rawId":id,"type":"public-key",
        "response":response,
      ]
    }
    guard let credential,
          JSONSerialization.isValidJSONObject(credential),
          let data=try? JSONSerialization.data(withJSONObject:credential),
          data.count<=131072,
          let json=String(data:data,encoding:.utf8) else{
      error("PASSKEY_INVALID","OS did not return a valid WebAuthn credential")
      return
    }
    finish(json)
  }

  func authorizationController(controller:ASAuthorizationController,
      didCompleteWithError authError:Error){
    let cancelled=(authError as NSError).code ==
      ASAuthorizationError.canceled.rawValue
    error(cancelled ? "USER_CANCELLED" : "PASSKEY_UNAVAILABLE",
      cancelled ? "Passkey request cancelled" : "Platform credential request failed")
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }
}
