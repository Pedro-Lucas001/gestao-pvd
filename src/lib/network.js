// src/lib/network.js

export const fetchWithTimeout = async (url, options = {}, transport = fetch, timeout = 10000) => {
  const controller = new AbortController();
  
  const signal = options.signal 
    ? AbortSignal.any([options.signal, controller.signal]) 
    : controller.signal;

  const id = setTimeout(() => {
    controller.abort();
  }, timeout);

  try {
    const response = await transport(url, {
      ...options,
      signal,
    });
    clearTimeout(id);
    return response;
  } catch (error) {
    clearTimeout(id);
    if (error.name === 'AbortError' || error.message.includes('aborted')) {
      throw new Error('TEST_TIMEOUT', { cause: error });
    }
    throw error;
  }
};