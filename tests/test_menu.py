import json
import unittest
from pathlib import Path

MENU = json.loads((Path(__file__).resolve().parents[1] / 'src/data/menu.json').read_text())

class MenuTest(unittest.TestCase):
    def test_catalog_structure_and_portion_prices(self):
        self.assertEqual(len(MENU), 47)
        self.assertEqual(len({p['id'] for p in MENU}), 47)
        self.assertEqual(len({p['category'] for p in MENU}), 7)
        for product in MENU:
            self.assertIs(type(product['price']), int)
            self.assertGreater(product['price'], 0)
        portions = {p['id']:p['price'] for p in MENU if p['category']=='coxinhas'}
        self.assertEqual(portions, {f'coxinhas-{qty}':price for qty,price in [(5,100),(10,200),(15,300),(20,400),(25,500),(35,700),(50,1000),(75,1500),(100,2000),(125,2500)]})

    def test_confirmed_drinks_and_menu_specials(self):
        by_id = {p['id']:p for p in MENU}
        self.assertEqual((by_id['pet-2']['name'],by_id['pet-2']['price']), ('Santa Joana 200 ml',200))
        self.assertEqual((by_id['pet-3']['name'],by_id['pet-3']['price']), ('Antarctica 200 ml',300))
        self.assertEqual(by_id['x-tudo']['price'],1700)
        self.assertEqual(by_id['x-dogao']['price'],1500)
        self.assertEqual(by_id['extra-bacon']['price'],300)
