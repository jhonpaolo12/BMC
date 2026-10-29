import { corsHeaders } from "../_shared/cors.ts";
import {
  getOrderSessionId,
  updateOrder,
} from "../_shared/firestore.ts";

function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", {
      status: 200,
      headers: corsHeaders,
    });
  }

  if (request.method !== "POST") {
    return jsonResponse(
      { error: "Method not allowed" },
      405,
    );
  }

  try {
    const body = await request.json();

    const orderId = body.order_id?.toString().trim();

    let sessionId = body.session_id?.toString().trim();

    if (!orderId) {
      return jsonResponse(
        { error: "Missing order_id" },
        400,
      );
    }

    if (!sessionId) {
      sessionId = await getOrderSessionId(orderId);
    }

    if (!sessionId) {
      return jsonResponse(
        {
          error:
            "No Xendit session is linked to this order",
        },
        400,
      );
    }

    const secretKey = Deno.env.get(
      "XENDIT_SECRET_KEY",
    );

    if (!secretKey) {
      return jsonResponse(
        {
          error:
            "XENDIT_SECRET_KEY is not configured",
        },
        500,
      );
    }

    const xenditResponse = await fetch(
      "https://api.xendit.co/sessions/" +
        encodeURIComponent(sessionId),
      {
        headers: {
          "Authorization":
            `Basic ${btoa(`${secretKey}:`)}`,
        },
      },
    );

    const xenditData = await xenditResponse.json();

    if (xenditResponse.status === 404) {
      return jsonResponse(
        {
          error: "Xendit session not found",
        },
        404,
      );
    }

    if (!xenditResponse.ok) {
      console.error(
        "Xendit status error:",
        JSON.stringify(xenditData),
      );

      return jsonResponse(
        {
          error:
            "Unable to read the Xendit session",
          details: xenditData,
        },
        xenditResponse.status,
      );
    }

    const xenditStatus = String(
      xenditData.status ?? "ACTIVE",
    ).toUpperCase();

    let paymentStatus = "awaiting_payment";
    let orderStatus = "pending";
    let legacyStatus = "PENDING";
    let paidAt: string | undefined;

    if (xenditStatus === "COMPLETED") {
      paymentStatus = "paid";
      orderStatus = "paid";
      legacyStatus = "PAID";
      paidAt = new Date().toISOString();
    } else if (xenditStatus === "EXPIRED") {
      paymentStatus = "failed";
      orderStatus = "failed";
      legacyStatus = "FAILED";
    } else if (
      xenditStatus === "CANCELED" ||
      xenditStatus === "CANCELLED"
    ) {
      paymentStatus = "cancelled";
      orderStatus = "cancelled";
      legacyStatus = "CANCELLED";
    }

    let firestoreUpdated = true;

    try {
      await updateOrder(orderId, {
        payment_status: paymentStatus,
        order_status: orderStatus,
        status: legacyStatus,
        updated_at: new Date().toISOString(),
        ...(paidAt ? { paid_at: paidAt } : {}),
      });
    } catch (error) {
      firestoreUpdated = false;

      console.error(
        "Firestore update failed:",
        error,
      );
    }

    return jsonResponse({
      order_id: orderId,
      session_id: sessionId,
      xendit_status: xenditStatus,
      payment_status: paymentStatus,
      order_status: orderStatus,
      firestore_updated: firestoreUpdated,
    });
  } catch (error) {
    console.error(
      "verify-xendit-payment error:",
      error,
    );

    return jsonResponse(
      {
        error:
          error instanceof Error
            ? error.message
            : "Unknown error",
      },
      500,
    );
  }
});
