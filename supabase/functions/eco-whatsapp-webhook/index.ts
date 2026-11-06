import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  // Tratamento de CORS para chamadas externas
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    // O payload recebido da IA do WhatsApp (ex: Dialogflow, Typebot, Chatwoot)
    const { customer_name, phone, total_amount, items } = await req.json()

    // 1. Cria o Pedido Principal (Delivery automático via WhatsApp)
    const { data: order, error: orderError } = await supabaseClient
      .from('orders')
      .insert({
        customer_name: `${customer_name} (WhatsApp)`,
        order_type: 'delivery',
        status: 'pending',
        total_amount: total_amount
      })
      .select()
      .single()

    if (orderError) throw orderError

    // 2. Prepara e Insere os Itens do Pedido
    const orderItems = items.map((item: any) => ({
      order_id: order.id,
      product_id: item.product_id,
      quantity: item.quantity,
      modifiers: item.modifiers || [] // Injeta modificadores da IA (ex: sem cebola)
    }))

    const { error: itemsError } = await supabaseClient
      .from('order_items')
      .insert(orderItems)

    if (itemsError) throw itemsError

    return new Response(
      JSON.stringify({ success: true, message: 'Pedido injetado no KDS com sucesso', order_id: order.id }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
    )

  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
    )
  }
})