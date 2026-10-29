import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

function base64UrlEncode(data: string): string {
  return btoa(data)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "")
}

function base64UrlEncodeBytes(bytes: Uint8Array): string {
  let binary = ""
  for (const byte of bytes) {
    binary += String.fromCharCode(byte)
  }

  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "")
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "")

  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)

  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i)
  }

  return bytes.buffer
}

async function getFirebaseAccessToken(
  serviceAccount: Record<string, string>,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000)

  const header = {
    alg: "RS256",
    typ: "JWT",
  }

  const claimSet = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/datastore",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }

  const encodedHeader = base64UrlEncode(JSON.stringify(header))
  const encodedClaimSet = base64UrlEncode(JSON.stringify(claimSet))

  const unsignedToken =
    `${encodedHeader}.${encodedClaimSet}`

  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(serviceAccount.private_key),
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["sign"],
  )

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    privateKey,
    new TextEncoder().encode(unsignedToken),
  )

  const jwt =
    `${unsignedToken}.${base64UrlEncodeBytes(new Uint8Array(signature))}`

  const response = await fetch(
    "https://oauth2.googleapis.com/token",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body:
        `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${encodeURIComponent(jwt)}`,
    },
  )

  if (!response.ok) {
    const errorText = await response.text()
    throw new Error(
      `Firebase OAuth token failed: ${errorText}`,
    )
  }

  const tokenData = await response.json()

  return tokenData.access_token
}

async function updateFirestoreOrder(
  orderId: string,
  status: string,
): Promise<void> {
  const encodedServiceAccount = Deno.env.get(
    "FIREBASE_SERVICE_ACCOUNT_BASE64",
  )

  if (!encodedServiceAccount) {
    throw new Error(
      "FIREBASE_SERVICE_ACCOUNT_BASE64 secret is missing",
    )
  }

  const serviceAccountJson = atob(encodedServiceAccount)
  const serviceAccount = JSON.parse(serviceAccountJson)

  const accessToken = await getFirebaseAccessToken(
    serviceAccount,
  )

  const projectId = serviceAccount.project_id

  const firestoreUrl =
    `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/orders/${orderId}?updateMask.fieldPaths=status`

  const response = await fetch(firestoreUrl, {
    method: "PATCH",
    headers: {
      "Authorization": `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      fields: {
        status: {
          stringValue: status,
        },
      },
    }),
  })

  if (!response.ok) {
    const errorText = await response.text()

    throw new Error(
      `Firestore update failed: ${errorText}`,
    )
  }
}

serve(async (req) => {
  try {
    // -----------------------------------------
    // 1. Verify Xendit webhook token
    // -----------------------------------------

    const callbackToken =
      req.headers.get("x-callback-token")

    const expectedToken =
      Deno.env.get("XENDIT_WEBHOOK_TOKEN")

    if (
      !expectedToken ||
      callbackToken !== expectedToken
    ) {
      return new Response(
        "Unauthorized webhook caller",
        {
          status: 401,
        },
      )
    }

    // -----------------------------------------
    // 2. Read Xendit webhook
    // -----------------------------------------

    const payload = await req.json()

    console.log(
      "Xendit webhook received:",
      JSON.stringify(payload),
    )

    const event = payload.event
    const data = payload.data

    if (!event || !data) {
      return new Response(
        JSON.stringify({
          error: "Invalid webhook payload",
        }),
        {
          status: 400,
          headers: {
            "Content-Type": "application/json",
          },
        },
      )
    }

    // -----------------------------------------
    // 3. Get reference ID
    // -----------------------------------------

    const referenceId = data.reference_id

    if (!referenceId) {
      return new Response(
        JSON.stringify({
          error: "Missing reference_id",
        }),
        {
          status: 400,
          headers: {
            "Content-Type": "application/json",
          },
        },
      )
    }

    // Our create-xendit-payment function creates:
    //
    // plaintees-${orderId}
    //

    if (!referenceId.startsWith("plaintees-")) {
      console.log(
        "Ignoring unrelated reference:",
        referenceId,
      )

      return new Response(
        JSON.stringify({
          received: true,
          ignored: true,
        }),
        {
          status: 200,
          headers: {
            "Content-Type": "application/json",
          },
        },
      )
    }

    const orderId =
      referenceId.replace("plaintees-", "")

    if (!orderId) {
      throw new Error(
        "Could not determine Firebase order ID",
      )
    }

    // -----------------------------------------
    // 4. Convert Xendit event to order status
    // -----------------------------------------

    let orderStatus: string

    if (event === "payment_session.completed") {
      orderStatus = "PAID"
    } else if (event === "payment_session.expired") {
      orderStatus = "FAILED"
    } else {
      console.log(
        "Ignoring unsupported event:",
        event,
      )

      return new Response(
        JSON.stringify({
          received: true,
          ignored: true,
          event,
        }),
        {
          status: 200,
          headers: {
            "Content-Type": "application/json",
          },
        },
      )
    }

    // -----------------------------------------
    // 5. Update Firebase Firestore
    // -----------------------------------------

    await updateFirestoreOrder(
      orderId,
      orderStatus,
    )

    console.log(
      `Order ${orderId} updated to ${orderStatus}`,
    )

    // -----------------------------------------
    // 6. Tell Xendit we received the webhook
    // -----------------------------------------

    return new Response(
      JSON.stringify({
        received: true,
        order_id: orderId,
        status: orderStatus,
      }),
      {
        status: 200,
        headers: {
          "Content-Type": "application/json",
        },
      },
    )
  } catch (error) {
    console.error("Webhook error:", error)

    return new Response(
      JSON.stringify({
        error:
          error instanceof Error
            ? error.message
            : "Unknown error",
      }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
        },
      },
    )
  }
})