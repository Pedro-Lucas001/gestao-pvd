import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { phone, action } = await req.json()

    if (action === 'delete') {
      // Chama a função SQL RPC que criámos
      const { data, error } = await supabaseClient.rpc('anonymize_customer_data', {
        target_phone: phone
      })

      if (error) throw error

      if (data) {
        return new Response(
          JSON.stringify({ success: true, message: 'Dados anonimizados com sucesso.' }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 200 }
        )
      } else {
        return new Response(
          JSON.stringify({ success: false, message: 'Cliente não encontrado.' }),
          { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 404 }
        )
      }
    }

    throw new Error('Ação não suportada')

  } catch (error) {
    const message = error !== null && typeof error === 'object' && 'message' in error
      ? String(error.message)
      : String(error)
    return new Response(
      JSON.stringify({ error: message }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' }, status: 400 }
    )
  }
})
