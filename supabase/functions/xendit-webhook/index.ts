import { updateOrder } from "../_shared/firestore.ts";

function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (request) => {
  try {
    // Xendit sends the callback token configured in the
    // Xendit dashboard. Reject anything else.
    const callbackToken = request.headers.get(
      "x-callback-token",
    );

    const expectedToken = Deno.env.get(
      "XENDIT_WEBHOOK_TOKEN",
    );

    if (
      !expectedToken ||
      callbackToken !== expectedToken
    ) {
      return new Response(
        "Unauthorized webhook caller",
        { status: 401 },
      );
    }

    const payload = await request.json();

    console.log(
      "Xendit webhook received:",
      JSON.stringify(payload),
    );

    const data = payload.data ?? payload;
    const event = String(payload.event ?? "");
    const xenditStatus = String(
      data.status ?? "",
    ).toUpperCase();

    const referenceId = data.reference_id
      ?.toString()
      .trim();

    if (!referenceId) {
      return jsonResponse(
        { error: "Missing reference_id" },
        400,
      );
    }

    if (!referenceId.startsWith("plaintees-")) {
      return jsonResponse({
        received: true,
        ignored: true,
      });
    }

    const orderId = referenceId.replace(
      "plaintees-",
      "",
    );

    if (!orderId) {
      return jsonResponse(
        {
          error:
            "Could not determine the Firebase order ID",
        },
        400,
      );
    }

    let paymentStatus: string | null = null;
    let orderStatus: string | null = null;
    let legacyStatus: string | null = null;
    let paidAt: string | undefined;

    if (
      event === "payment_session.completed" ||
      xenditStatus === "COMPLETED"
    ) {
      paymentStatus = "paid";
      orderStatus = "paid";
      legacyStatus = "PAID";
      paidAt = new Date().toISOString();
    } else if (
      event === "payment_session.expired" ||
      xenditStatus === "EXPIRED"
    ) {
      paymentStatus = "failed";
      orderStatus = "failed";
      legacyStatus = "FAILED";
    } else if (
      event === "payment_session.canceled" ||
      event === "payment_session.cancelled" ||
      xenditStatus === "CANCELED" ||
      xenditStatus === "CANCELLED"
    ) {
      paymentStatus = "cancelled";
      orderStatus = "cancelled";
      legacyStatus = "CANCELLED";
    }

    if (!paymentStatus || !orderStatus || !legacyStatus) {
      return jsonResponse({
        received: true,
        ignored: true,
        event,
        status: xenditStatus,
      });
    }

    await updateOrder(orderId, {
      payment_status: paymentStatus,
      order_status: orderStatus,
      status: legacyStatus,
      updated_at: new Date().toISOString(),
      ...(paidAt ? { paid_at: paidAt } : {}),
    });

    console.log(
      `Order ${orderId} updated to ${paymentStatus}`,
    );

    return jsonResponse({
      received: true,
      order_id: orderId,
      payment_status: paymentStatus,
      order_status: orderStatus,
    });
  } catch (error) {
    console.error("Webhook error:", error);

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
