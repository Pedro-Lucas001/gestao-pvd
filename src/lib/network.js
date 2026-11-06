// Utilizando a API nativa do IndexedDB para máxima performance
const DB_NAME = 'planeta_lanches_db';
const STORE_NAME = 'offline_orders';

// Inicializa o banco de dados local
const initDB = () => {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, 1);
    request.onupgradeneeded = (e) => {
      const db = e.target.result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME, { keyPath: 'local_id' });
      }
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
};

// Guarda um pedido na fila quando não há internet
export const saveOrderOffline = async (orderPayload) => {
  const db = await initDB();
  const transaction = db.transaction(STORE_NAME, 'readwrite');
  const store = transaction.objectStore(STORE_NAME);
  
  // Adiciona um ID local temporário e a data
  const localOrder = {
    ...orderPayload,
    local_id: `offline_${Date.now()}`,
    saved_at: new Date().toISOString()
  };
  
  store.add(localOrder);
  return localOrder;
};

// Busca todos os pedidos retidos
export const getOfflineOrders = async () => {
  const db = await initDB();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readonly');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.getAll();
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
};

// Apaga o pedido da fila local após ser enviado com sucesso ao Supabase
export const removeOfflineOrder = async (localId) => {
  const db = await initDB();
  const transaction = db.transaction(STORE_NAME, 'readwrite');
  transaction.objectStore(STORE_NAME).delete(localId);
};