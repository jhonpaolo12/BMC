import { corsHeaders } from "../_shared/cors.ts";
import { updateOrder } from "../_shared/firestore.ts";

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

    const amount = Number(
      Number(body.amount).toFixed(2),
    );

    const orderId = body.order_id?.toString().trim();

    const items = Array.isArray(body.items)
      ? body.items
      : [];

    if (!Number.isFinite(amount) || amount <= 0) {
      return jsonResponse(
        { error: "Invalid payment amount" },
        400,
      );
    }

    if (!orderId) {
      return jsonResponse(
        { error: "Missing order_id" },
        400,
      );
    }

    if (items.length > 0) {
      const computedTotal = items.reduce(
        (sum: number, item: Record<string, unknown>) => {
          const subtotal = Number(
            item.subtotal ??
              Number(item.price ?? 0) *
                Number(item.quantity ?? 1),
          );

          return sum +
            (Number.isFinite(subtotal) ? subtotal : 0);
        },
        0,
      );

      if (Math.abs(computedTotal - amount) > 0.01) {
        return jsonResponse(
          {
            error:
              "Order total does not match the cart items",
          },
          400,
        );
      }
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

    const referenceId = `plaintees-${orderId}`;

    const returnUrl =
      "https://plaintees-e-commerce.web.app/" +
      "payment-return.html?order_id=" +
      encodeURIComponent(orderId);

    const xenditItems = items
      .map((item: Record<string, unknown>, index: number) => {
        const price = Number(item.price ?? 0);
        const quantity = Number(item.quantity ?? 1);

        if (
          !Number.isFinite(price) ||
          price <= 0 ||
          !Number.isFinite(quantity) ||
          quantity <= 0
        ) {
          return null;
        }

        return {
          reference_id: `item-${index + 1}`,
          type: "PHYSICAL_PRODUCT",
          name:
            String(item.product_name ?? "") ||
            `PlainTees Item ${index + 1}`,
          net_unit_amount: price,
          quantity,
          category: "Apparel",
        };
      })
      .filter((item) => item !== null);

    const xenditResponse = await fetch(
      "https://api.xendit.co/sessions",
      {
        method: "POST",
        headers: {
          "Authorization":
            `Basic ${btoa(`${secretKey}:`)}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          reference_id: referenceId,
          session_type: "PAY",
          mode: "PAYMENT_LINK",
          amount,
          currency: "PHP",
          country: "PH",
          locale: "en",
          description: `PlainTees Order ${orderId}`,
          success_return_url: returnUrl,
          cancel_return_url: returnUrl,
          ...(xenditItems.length > 0
            ? { items: xenditItems }
            : {}),
        }),
      },
    );

    const xenditData = await xenditResponse.json();

    if (!xenditResponse.ok) {
      console.error(
        "Xendit error:",
        JSON.stringify(xenditData),
      );

      return jsonResponse(
        {
          error:
            "Xendit payment session failed",
          details: xenditData,
        },
        xenditResponse.status,
      );
    }

    const paymentLinkUrl =
      xenditData.payment_link_url;

    const paymentSessionId =
      xenditData.payment_session_id;

    if (!paymentLinkUrl || !paymentSessionId) {
      return jsonResponse(
        {
          error:
            "Xendit did not return a payment link",
          details: xenditData,
        },
        502,
      );
    }

    // Keep Firestore as the source of truth. If this update
    // fails, the app can still open the payment link and the
    // webhook/verify function can update the order later.
    let firestoreUpdated = true;

    try {
      await updateOrder(orderId, {
        payment_status: "awaiting_payment",
        order_status: "pending",
        status: "PENDING",
        payment_link_url: paymentLinkUrl,
        xendit_session_id: paymentSessionId,
        xendit_reference_id: referenceId,
        updated_at: new Date().toISOString(),
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
      payment_link_url: paymentLinkUrl,
      payment_session_id: paymentSessionId,
      reference_id:
        xenditData.reference_id ?? referenceId,
      firestore_updated: firestoreUpdated,
    });
  } catch (error) {
    console.error(
      "create-xendit-payment error:",
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
