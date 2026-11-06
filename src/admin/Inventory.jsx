import React, { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';

export default function Inventory() {
  const [products, setProducts] = useState([]);
  const [ingredients, setIngredients] = useState([]);
  const [selectedProduct, setSelectedProduct] = useState(null);
  const [recipe, setRecipe] = useState([]);
  
  // Estados para o formulário de adição de insumo
  const [selectedIngredient, setSelectedIngredient] = useState('');
  const [quantity, setQuantity] = useState('');

  useEffect(() => {
    fetchBaseData();
  }, []);

  const fetchBaseData = async () => {
    const [prodRes, ingRes] = await Promise.all([
      supabase.from('products').select('*').order('name'),
      supabase.from('ingredients').select('*').order('name')
    ]);
    if (prodRes.data) setProducts(prodRes.data);
    if (ingRes.data) setIngredients(ingRes.data);
  };

  const loadRecipe = async (product) => {
    setSelectedProduct(product);
    const { data } = await supabase
      .from('technical_sheets')
      .select('*, ingredients(name, unit)')
      .eq('product_id', product.id);
    
    if (data) setRecipe(data);
  };

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
      loadRecipe(selectedProduct); // Recarrega a lista
    } else {
      alert('Erro ao vincular insumo. Verifique se já existe na ficha.');
    }
  };

  const removeIngredient = async (sheetId) => {
    await supabase.from('technical_sheets').delete().eq('id', sheetId);
    loadRecipe(selectedProduct);
  };

  return (
    <div className="min-h-screen bg-dark-900 text-white font-sans p-8 flex gap-8">
      
      {/* COLUNA ESQUERDA: Lista de Produtos */}
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

      {/* COLUNA DIREITA: Construtor da Ficha Técnica */}
      <main className="flex-1 bg-dark-800 border border-dark-700 rounded-2xl shadow-glass flex flex-col overflow-hidden">
        {selectedProduct ? (
          <>
            <div className="p-6 border-b border-dark-700 flex justify-between items-center bg-dark-900">
              <div>
                <h2 className="text-2xl font-bold text-white">Ficha Técnica</h2>
                <h3 className="text-brasa-500 text-lg font-bold">{selectedProduct.name}</h3>
              </div>
              <span className="bg-dark-800 text-gray-400 px-4 py-2 rounded-lg text-sm border border-dark-700">
                Custo Estimado: R$ --
              </span>
            </div>

            <div className="p-6 flex-1 overflow-y-auto">
              {/* Formulário de Adição Rápida */}
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

              {/* Lista da Ficha Técnica */}
              <div className="space-y-3">
                {recipe.length === 0 ? (
                  <div className="text-center p-12 border-2 border-dashed border-dark-700 rounded-xl text-gray-500 font-bold">
                    Nenhum insumo vinculado a este produto.
                  </div>
                ) : (
                  recipe.map(item => (
                    <div key={item.id} className="flex justify-between items-center bg-dark-900 p-4 rounded-xl border border-dark-700 group hover:border-dark-500 transition-colors">
                      <div className="flex items-center gap-4">
                        <div className="w-12 h-12 bg-dark-800 rounded-lg border border-dark-700 flex items-center justify-center font-bold text-brasa-500">
                          {item.quantity_needed}
                        </div>
                        <div>
                          <p className="font-bold text-white text-lg">{item.ingredients?.name}</p>
                          <p className="text-sm text-gray-400 uppercase tracking-wider">Medida: {item.ingredients?.unit}</p>
                        </div>
                      </div>
                      <button 
                        onClick={() => removeIngredient(item.id)}
                        className="text-gray-500 hover:text-red-500 p-2 transition-colors"
                      >
                        <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path></svg>
                      </button>
                    </div>
                  ))
                )}
              </div>
            </div>
          </>
        ) : (
          <div className="flex-1 flex flex-col items-center justify-center text-gray-500">
            <svg className="w-24 h-24 mb-4 opacity-20" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="1" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-3 7h3m-3 4h3m-6-4h.01M9 16h.01"></path></svg>
            <p className="text-xl font-bold">Selecione um produto</p>
            <p className="text-sm mt-2">Para visualizar e editar a sua ficha técnica</p>
          </div>
        )}
      </main>
    </div>
  );
}