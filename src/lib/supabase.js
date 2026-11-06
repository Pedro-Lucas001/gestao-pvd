import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL;
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

// Validação Estrita: Impede que o deploy na Vercel falhe silenciosamente
if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error('Variáveis de ambiente do Supabase ausentes. Verifica o ficheiro .env ou as definições da Vercel.');
}

// Política de Retentativas (Exponential Backoff)
const customFetch = async (url, options) => {
  let retries = 3;
  let delay = 1000; // Começa com 1 segundo
  
  while (retries > 0) {
    try {
      const response = await fetch(url, options);
      // Se for um erro de servidor (5xx), forçamos o catch para tentar novamente
      if (!response.ok && response.status >= 500) throw new Error('Erro de servidor temporário');
      return response;
    } catch (error) {
      retries -= 1;
      if (retries === 0) throw error;
      await new Promise(res => setTimeout(res, delay));
      delay *= 2; // Dobra o tempo de espera a cada falha (1s, 2s, 4s)
    }
  }
};

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  global: {
    fetch: customFetch,
  },
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  }
});