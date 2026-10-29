import { corsHeaders } from "https://esm.sh/@supabase/supabase-js@2.95.0/cors";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.95.0";

Deno.serve(async (req) => {
  // ==========================================
  // HANDLE CORS PREFLIGHT
  // ==========================================

  if (req.method === "OPTIONS") {
    return new Response("ok", {
      status: 200,
      headers: corsHeaders,
    });
  }

  try {
    // ==========================================
    // ONLY ALLOW POST REQUESTS
    // ==========================================

    if (req.method !== "POST") {
      return new Response(
        JSON.stringify({
          error: "Method not allowed",
        }),
        {
          status: 405,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
          },
        },
      );
    }

    // ==========================================
    // READ REQUEST BODY
    // ==========================================

    const body = await req.json();

    const amount = Number(body.amount);
    const orderId = body.order_id?.toString();
    const items = Array.isArray(body.items) ? body.items : [];

    // ==========================================
    // VALIDATE AMOUNT
    // ==========================================

    if (!amount || amount <= 0) {
      return new Response(
        JSON.stringify({
          error: "Invalid amount",
        }),
        {
          status: 400,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
          },
        },
      );
    }

    // ==========================================
    // VALIDATE ORDER ID
    // ==========================================

    if (!orderId || orderId.trim() === "") {
      return new Response(
        JSON.stringify({
          error: "Missing order_id",
        }),
        {
          status: 400,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
          },
        },
      );
    }

    // ==========================================
    // GET SECRETS
    // ==========================================

    const secretKey = Deno.env.get("XENDIT_SECRET_KEY");

    const supabaseUrl = Deno.env.get("SUPABASE_URL");

    const serviceRoleKey = Deno.env.get(
      "SUPABASE_SERVICE_ROLE_KEY",
    );

    if (!secretKey) {
      return new Response(
        JSON.stringify({
          error: "XENDIT_SECRET_KEY is not configured",
        }),
        {
          status: 500,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
          },
        },
      );
    }

    if (!supabaseUrl || !serviceRoleKey) {
      return new Response(
        JSON.stringify({
          error: "Supabase server configuration is missing",
        }),
        {
          status: 500,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
          },
        },
      );
    }

    // ==========================================
    // CREATE SUPABASE ADMIN CLIENT
    // ==========================================

    const supabaseAdmin = createClient(
      supabaseUrl,
      serviceRoleKey,
    );

    // ==========================================
    // SAVE ORDER TO SUPABASE
    // ==========================================

    const { error: orderError } =
      await supabaseAdmin
        .from("orders")
        .upsert(
          {
            firebase_order_id: orderId,
            total: amount,
            payment_status: "pending",
          },
          {
            onConflict: "firebase_order_id",
          },
        );

    if (orderError) {
      console.error(
        "Order insert error:",
        orderError,
      );

      return new Response(
        JSON.stringify({
          error: "Failed to save order",
          details: orderError.message,
        }),
        {
          status: 500,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
          },
        },
      );
    }

    // ==========================================
    // SAVE ORDER ITEMS
    // ==========================================

    if (items.length > 0) {
      // Remove old items first in case this order
      // is being retried.
      const { error: deleteError } =
        await supabaseAdmin
          .from("order_items")
          .delete()
          .eq("firebase_order_id", orderId);

      if (deleteError) {
        console.error(
          "Delete old order items error:",
          deleteError,
        );

        return new Response(
          JSON.stringify({
            error: "Failed to prepare order items",
            details: deleteError.message,
          }),
          {
            status: 500,
            headers: {
              ...corsHeaders,
              "Content-Type": "application/json",
            },
          },
        );
      }

      const orderItems = items.map((item: any) => ({
        firebase_order_id: orderId,
        product_name: item.product_name ?? "",
        size: item.size ?? "",
        quantity: Number(item.quantity ?? 1),
        price: Number(item.price ?? 0),
        subtotal: Number(item.subtotal ?? 0),
        image_path: item.image_path ?? null,
      }));

      const { error: itemsError } =
        await supabaseAdmin
          .from("order_items")
          .insert(orderItems);

      if (itemsError) {
        console.error(
          "Order items insert error:",
          itemsError,
        );

        return new Response(
          JSON.stringify({
            error: "Failed to save order items",
            details: itemsError.message,
          }),
          {
            status: 500,
            headers: {
              ...corsHeaders,
              "Content-Type": "application/json",
            },
          },
        );
      }
    }

    // ==========================================
    // CREATE XENDIT REFERENCE ID
    // ==========================================

    const referenceId = `plaintees-${orderId}`;

    // ==========================================
    // CREATE XENDIT PAYMENT SESSION
    // ==========================================

    const xenditResponse = await fetch(
      "https://api.xendit.co/sessions",
      {
        method: "POST",

        headers: {
          "Authorization": `Basic ${btoa(`${secretKey}:`)}`,
          "Content-Type": "application/json",
        },

        body: JSON.stringify({
          reference_id: referenceId,
          session_type: "PAY",
          mode: "PAYMENT_LINK",
          amount: amount,
          currency: "PHP",
          country: "PH",
          locale: "en",
          description: "PlainTees Order",

          success_return_url:
            "https://plaintees-e-commerce.web.app/payment-return.html",

          cancel_return_url:
            "https://plaintees-e-commerce.web.app/payment-return.html",
        }),
      },
    );

    // ==========================================
    // READ XENDIT RESPONSE
    // ==========================================

    const responseData = await xenditResponse.json();

    // ==========================================
    // HANDLE XENDIT ERROR
    // ==========================================

    if (!xenditResponse.ok) {
      console.error(
        "Xendit error:",
        JSON.stringify(responseData),
      );

      return new Response(
        JSON.stringify({
          error: "Xendit payment session failed",
          details: responseData,
        }),
        {
          status: xenditResponse.status,
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
          },
        },
      );
    }

    // ==========================================
    // RETURN PAYMENT INFORMATION TO FLUTTER
    // ==========================================

    return new Response(
      JSON.stringify({
        payment_link_url:
          responseData.payment_link_url,
        payment_session_id:
          responseData.payment_session_id,
        reference_id:
          responseData.reference_id,
      }),
      {
        status: 200,
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      },
    );
  } catch (error) {
    console.error(
      "Payment error:",
      error,
    );

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
          ...corsHeaders,
          "Content-Type": "application/json",
        },
      },
    );
  }
});