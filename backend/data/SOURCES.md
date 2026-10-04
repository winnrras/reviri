# Where Reviri's numbers come from

Every number the app shows is computed from `canonical.json` (shelf life, price, CO2e per
ingredient). This file says where each value comes from. Values marked **estimate** have no
public source yet; say so if a judge asks.

## Sources

- **Shelf life: USDA FoodKeeper** (USDA Food Safety and Inspection Service), the US
  government's food storage guidance, via the FoodKeeper data export
  ([catalog.data.gov/dataset/fsis-foodkeeper-data](https://catalog.data.gov/dataset/fsis-foodkeeper-data);
  copy used: [github.com/jelera/food-shelflife-db](https://github.com/jelera/food-shelflife-db),
  `lib/seeds/ingredients.csv`). We take the **low end** of each range, counted from the date of
  purchase, for where the food is normally stored. Low end = conservative, which suits "use it
  before it spoils".
- **Price: US Bureau of Labor Statistics, Average Price Data**, U.S. city average, **August 2026**
  (latest month available), fetched from the BLS public API. Series titles checked on FRED
  (St. Louis Fed). Converted to $/kg (1 lb = 0.4536 kg, 1 US gal ≈ 3.785 kg of milk).
- **CO2e: Poore & Nemecek (2018), "Reducing food's environmental impacts through producers and
  consumers", *Science* 360:987-992**, global median kg CO2e per kg of product, via Our World in
  Data ([ourworldindata.org/grapher/ghg-per-kg-poore](https://ourworldindata.org/grapher/ghg-per-kg-poore)).
  The dataset is by food group, so each ingredient uses its group.

## Per ingredient

| Ingredient | Shelf life (days) | FoodKeeper entry | Price $/kg | Price source | CO2e kg/kg | CO2e group |
| --- | --- | --- | --- | --- | --- | --- |
| Chicken breast | 1 | Chicken parts, breast halves, boneless: fridge 1-2 days | 9.20 | BLS APU0000FF1101 chicken breast, boneless, $4.173/lb | 9.87 | Poultry Meat |
| Heavy cream | 10 | Cream, heavy: fridge 10 days | 8.00 | estimate | 3.15 | Milk (closest group; cream is likely higher) |
| Spinach | 3 | Lettuce, leaf, spinach: fridge 3-7 days | 12.00 | estimate | 0.53 | Other Vegetables |
| Mushrooms | 3 | Mushrooms: fridge 3-7 days | 10.00 | estimate | 0.53 | Other Vegetables |
| Eggs | 21 | Eggs, in shell: fridge 3-5 weeks | 3.79 | BLS APU0000708111 eggs, grade A large, $2.272/dozen (600 g) | 4.67 | Eggs |
| Cheddar | 180 | Cheese, hard (cheddar, swiss, block parmesan): fridge 6 months unopened | 13.19 | BLS APU0000710212 cheddar, $5.983/lb | 23.88 | Cheese |
| Onion | 30 | Onions, yellow/white/red: pantry 1 month | 2.50 | estimate | 0.50 | Onions & Leeks |
| Garlic | 30 | Garlic: pantry 1 month | 12.00 | estimate | 0.50 | Onions & Leeks |
| Parmesan | 180 | Cheese, hard (block parmesan): fridge 6 months unopened | 25.00 | estimate | 23.88 | Cheese |
| Butter | 30 | Butter: fridge 1-2 months | 8.86 | BLS APU0000FS1101 butter, stick, $4.021/lb | 4.0 | estimate (dairy category; not in the dataset) |
| Pasta | 730 | Pasta, dry, without eggs: pantry 2 years | 3.03 | BLS APU0000701322 spaghetti and macaroni, $1.374/lb | 1.57 | Wheat & Rye |
| Rice | 730 | Rice, white or wild: pantry 2 years | 2.45 | BLS APU0000701312 rice, white, long grain, $1.111/lb | 4.45 | Rice |
| Tomatoes | 7 | Tomatoes: pantry until ripe, then 7 days | 4.36 | BLS APU0000712311 tomatoes, field grown, $1.977/lb | 2.09 | Tomatoes |
| Bell pepper | 4 | Peppers: fridge 4-14 days | 6.00 | estimate | 0.53 | Other Vegetables |
| Cilantro | 14 | Cilantro: fridge 2-3 weeks | 25.00 | estimate | 0.53 | Other Vegetables |
| Soy sauce | 1095 | Soy sauce or teriyaki sauce: pantry 3 years unopened | 6.00 | estimate | 1.5 | estimate (pantry category; not in the dataset) |
| Lemon | 10 | Citrus fruit: fridge 10-21 days | 5.00 | estimate | 0.39 | Citrus Fruit |
| Broccoli | 3 | Broccoli: fridge 3-5 days | 5.00 | estimate | 0.51 | Brassicas |
| Tortillas | 90 | Tortillas, flour: pantry 3 months | 6.00 | estimate | 1.57 | Wheat & Rye |
| Black beans | 730 | Canned goods, low acid: pantry 2-5 years | 3.00 | estimate | 1.79 | Other Pulses |
| Olive oil | 180 | Oils, olive or vegetable: pantry 6-12 months | 12.00 | estimate | 1.5 | estimate (pantry category; olive oil isn't in the OWID table) |
| Milk | 7 | Milk: FoodKeeper says use the package date | 1.12 | BLS APU0000709112 whole milk, $4.229/gal | 3.15 | Milk |
| Apple juice | 8 | Fruit juice in cartons: fridge 8-12 days after opening | 1.60 | estimate | 0.43 | Apples (fruit basis) |
| Orange juice | 7 | Orange juice, carton: fridge 7-10 days after opening | 2.60 | estimate | 0.39 | Citrus Fruit (fruit basis) |
| Yogurt | 7 | Yogurt: fridge 1-2 weeks | 4.40 | estimate | 3.15 | Milk (closest group) |

Milk's 7 days is our assumption for "use by the package date", not a FoodKeeper number.

## What this means for the app

- "Perishable" (worth rescuing) = shelf life of 14 days or less. With FoodKeeper values that's
  chicken, cream, spinach, mushrooms, tomatoes, peppers, cilantro, lemons, broccoli, milk,
  juices and yogurt.
- Money saved and CO2e avoided use these values for the food a suggested recipe used up.
  They are estimates of value, not measurements; the Savings tab says so.
