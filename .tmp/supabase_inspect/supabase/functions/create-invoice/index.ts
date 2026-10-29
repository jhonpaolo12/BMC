import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Handle browser preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { product_name, amount } = await req.json()

    // 1. Read keys from Supabase's secure environment vault
    const xenditSecret = Deno.env.get('XENDIT_SECRET_KEY') ?? ''
    const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

    // 2. Connect to database using the Service Role Key (bypasses RLS)
    const supabase = createClient(supabaseUrl, supabaseServiceKey)
    const externalId = `order_${new Date().getTime()}`

    // 3. Call Xendit API to create a payment link
    const basicAuth = btoa(`${xenditSecret}:`)
    const xenditRes = await fetch('https://api.xendit.co/v2/invoices', {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${basicAuth}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        external_id: externalId,
        amount: amount,
        description: `Order for ${product_name}`,
        currency: 'PHP',
      }),
    })

    const xenditData = await xenditRes.json()
    if (!xenditRes.ok) throw new Error(JSON.stringify(xenditData))

    // 4. Save the initial order as PENDING
    const { error: dbError } = await supabase.from('orders').insert({
      external_id: externalId,
      product_name: product_name,
      amount: amount,
      status: 'PENDING',
    })
    if (dbError) throw new Error(dbError.message)

    // 5. Return ONLY the safe payment link and order reference to Flutter
    return new Response(
      JSON.stringify({
        invoice_url: xenditData.invoice_url,
        external_id: externalId,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})