type ServiceAccount = {
  client_email: string;
  private_key: string;
  project_id: string;
};

type FirestoreFieldValue =
  | { stringValue: string }
  | { timestampValue: string }
  | { nullValue: null };

let cachedAccessToken:
  | { token: string; expiresAt: number }
  | null = null;

function base64UrlEncode(value: string): string {
  return btoa(value)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function base64UrlEncodeBytes(bytes: Uint8Array): string {
  let binary = "";

  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");

  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);

  for (let index = 0; index < binary.length; index++) {
    bytes[index] = binary.charCodeAt(index);
  }

  return bytes.buffer;
}

function readServiceAccount(): ServiceAccount {
  const encoded = Deno.env.get(
    "FIREBASE_SERVICE_ACCOUNT_BASE64",
  );

  if (!encoded) {
    throw new Error(
      "FIREBASE_SERVICE_ACCOUNT_BASE64 is not configured",
    );
  }

  return JSON.parse(atob(encoded)) as ServiceAccount;
}

async function getAccessToken(): Promise<{
  token: string;
  projectId: string;
}> {
  if (
    cachedAccessToken &&
    Date.now() < cachedAccessToken.expiresAt
  ) {
    const serviceAccount = readServiceAccount();

    return {
      token: cachedAccessToken.token,
      projectId: serviceAccount.project_id,
    };
  }

  const serviceAccount = readServiceAccount();
  const now = Math.floor(Date.now() / 1000);

  const encodedHeader = base64UrlEncode(
    JSON.stringify({
      alg: "RS256",
      typ: "JWT",
    }),
  );

  const encodedClaimSet = base64UrlEncode(
    JSON.stringify({
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/datastore",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    }),
  );

  const unsignedToken =
    `${encodedHeader}.${encodedClaimSet}`;

  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(serviceAccount.private_key),
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    privateKey,
    new TextEncoder().encode(unsignedToken),
  );

  const jwt =
    `${unsignedToken}.${base64UrlEncodeBytes(new Uint8Array(signature))}`;

  const response = await fetch(
    "https://oauth2.googleapis.com/token",
    {
      method: "POST",
      headers: {
        "Content-Type":
          "application/x-www-form-urlencoded",
      },
      body:
        `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${encodeURIComponent(jwt)}`,
    },
  );

  if (!response.ok) {
    const errorText = await response.text();

    throw new Error(
      `Firebase OAuth token failed: ${errorText}`,
    );
  }

  const tokenData = await response.json();

  cachedAccessToken = {
    token: tokenData.access_token,
    expiresAt: Date.now() + 50 * 60 * 1000,
  };

  return {
    token: tokenData.access_token,
    projectId: serviceAccount.project_id,
  };
}

function orderDocumentUrl(
  projectId: string,
  orderId: string,
): string {
  return (
    "https://firestore.googleapis.com/v1/projects/" +
    `${projectId}/databases/(default)/documents/orders/` +
    encodeURIComponent(orderId)
  );
}

export async function updateOrder(
  orderId: string,
  fields: Record<string, string | undefined>,
): Promise<void> {
  const { token, projectId } = await getAccessToken();

  const fieldPaths = Object.entries(fields)
    .filter(([, value]) => value !== undefined)
    .map(([key]) => key);

  if (fieldPaths.length === 0) {
    return;
  }

  const firestoreFields: Record<
    string,
    FirestoreFieldValue
  > = {};

  for (const [key, value] of Object.entries(fields)) {
    if (value === undefined) continue;

    if (key.endsWith("_at")) {
      firestoreFields[key] = {
        timestampValue: value,
      };
    } else {
      firestoreFields[key] = {
        stringValue: value,
      };
    }
  }

  const updateMask = fieldPaths
    .map(
      (path) =>
        `updateMask.fieldPaths=${encodeURIComponent(path)}`,
    )
    .join("&");

  const response = await fetch(
    `${orderDocumentUrl(projectId, orderId)}?${updateMask}&currentDocument.exists=true`,
    {
      method: "PATCH",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        fields: firestoreFields,
      }),
    },
  );

  if (!response.ok) {
    const errorText = await response.text();

    throw new Error(
      `Firestore update failed: ${errorText}`,
    );
  }
}

export async function getOrderSessionId(
  orderId: string,
): Promise<string | null> {
  const { token, projectId } = await getAccessToken();

  const response = await fetch(
    orderDocumentUrl(projectId, orderId),
    {
      headers: {
        "Authorization": `Bearer ${token}`,
      },
    },
  );

  if (response.status === 404) {
    return null;
  }

  if (!response.ok) {
    const errorText = await response.text();

    throw new Error(
      `Firestore read failed: ${errorText}`,
    );
  }

  const data = await response.json();

  return (
    data?.fields?.xendit_session_id?.stringValue ?? null
  );
}
