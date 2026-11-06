import { useState, useEffect, useCallback } from 'react';
import { supabase } from '../lib/supabase';

export default function Inventory() {
  const [products, setProducts] = useState([]);
  const [ingredients, setIngredients] = useState([]);
  const [selectedProduct, setSelectedProduct] = useState(null);
  const [recipe, setRecipe] = useState([]);
  
  const [selectedIngredient, setSelectedIngredient] = useState('');
  const [quantity, setQuantity] = useState('');

  const loadRecipe = useCallback(async (product) => {
    setSelectedProduct(product);
    const { data } = await supabase
      .from('technical_sheets')
      .select('*, ingredients(name, unit)')
      .eq('product_id', product.id);
    
    if (data) setRecipe(data);
  }, []);

  // Busca inicial segura de produtos
  useEffect(() => {
    let isMounted = true;
    async function fetchInitialData() {
      const [prodRes, ingRes] = await Promise.all([
        supabase.from('products').select('*').order('name'),
        supabase.from('ingredients').select('*').order('name')
      ]);
      if (isMounted) {
        if (prodRes.data) setProducts(prodRes.data);
        if (ingRes.data) setIngredients(ingRes.data);
      }
    }
    fetchInitialData();
    return () => { isMounted = false; };
  }, []);

  const addIngredientToRecipe = async (e) => {
    e.preventDefault();
    if (!selectedProduct || !selectedIngredient || !quantity) return;

    const newEntry = {
      product_id: selectedProduct.id,
      ingredient_id: selectedIngredient,
      quantity_needed: parseFloat(quantity)
    };

    const { error } = await supabase.from('technical_sheets').insert(newEntry);
    
    if (!error) {
      setQuantity('');
      setSelectedIngredient('');
      loadRecipe(selectedProduct);
    } else {
      alert('Erro ao vincular insumo.');
    }
  };

  const removeIngredient = async (sheetId) => {
    await supabase.from('technical_sheets').delete().eq('id', sheetId);
    if (selectedProduct) loadRecipe(selectedProduct);
  };

  return (
    <div className="min-h-screen bg-dark-900 text-white font-sans p-8 flex gap-8">
      <aside className="w-1/3 bg-dark-800 border border-dark-700 rounded-2xl flex flex-col overflow-hidden shadow-glass">
        <div className="p-6 border-b border-dark-700 bg-dark-900">
          <h2 className="text-xl font-bold text-white">Cardápio</h2>
          <p className="text-gray-400 text-sm">Selecione para editar a ficha</p>
        </div>
        <div className="flex-1 overflow-y-auto p-4 space-y-2">
          {products.map(prod => (
            <button
              key={prod.id}
              onClick={() => loadRecipe(prod)}
              className={`w-full text-left p-4 rounded-xl border transition-all font-bold ${
                selectedProduct?.id === prod.id 
                  ? 'bg-brasa-500/10 border-brasa-500 text-brasa-500' 
                  : 'bg-dark-900 border-dark-700 text-gray-300 hover:border-gray-500'
              }`}
            >
              {prod.name}
            </button>
          ))}
        </div>
      </aside>

      <main className="flex-1 bg-dark-800 border border-dark-700 rounded-2xl shadow-glass flex flex-col overflow-hidden">
        {selectedProduct ? (
          <>
            <div className="p-6 border-b border-dark-700 flex justify-between items-center bg-dark-900">
              <div>
                <h2 className="text-2xl font-bold text-white">Ficha Técnica</h2>
                <h3 className="text-brasa-500 text-lg font-bold">{selectedProduct.name}</h3>
              </div>
            </div>

            <div className="p-6 flex-1 overflow-y-auto">
              <form onSubmit={addIngredientToRecipe} className="flex gap-4 mb-8 bg-dark-900 p-4 rounded-xl border border-dark-700">
                <div className="flex-1">
                  <label className="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">Insumo</label>
                  <select 
                    value={selectedIngredient}
                    onChange={(e) => setSelectedIngredient(e.target.value)}
                    className="w-full bg-dark-800 border border-dark-700 rounded-lg p-3 text-white focus:border-brasa-500 outline-none"
                  >
                    <option value="">Selecione...</option>
                    {ingredients.map(ing => (
                      <option key={ing.id} value={ing.id}>{ing.name} ({ing.unit})</option>
                    ))}
                  </select>
                </div>
                <div className="w-48">
                  <label className="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">Quantidade</label>
                  <input 
                    type="number" 
                    step="0.001" 
                    min="0"
                    placeholder="Ex: 0.150"
                    value={quantity}
                    onChange={(e) => setQuantity(e.target.value)}
                    className="w-full bg-dark-800 border border-dark-700 rounded-lg p-3 text-white focus:border-brasa-500 outline-none"
                  />
                </div>
                <div className="flex items-end">
                  <button type="submit" className="bg-brasa-500 hover:bg-brasa-600 text-white font-bold px-6 py-3 rounded-lg shadow-brasa-glow transition-all">
                    Vincular
                  </button>
                </div>
              </form>

              <div className="space-y-3">
                {recipe.map(item => (
                  <div key={item.id} className="flex justify-between items-center bg-dark-900 p-4 rounded-xl border border-dark-700">
                    <p className="font-bold text-white">{item.ingredients?.name} - {item.quantity_needed} {item.ingredients?.unit}</p>
                    <button onClick={() => removeIngredient(item.id)} className="text-red-500 font-bold">Remover</button>
                  </div>
                ))}
              </div>
            </div>
          </>
        ) : (
          <div className="flex-1 flex items-center justify-center text-gray-500 font-bold">
            Selecione um produto ao lado.
          </div>
        )}
      </main>
    </div>
  );
}