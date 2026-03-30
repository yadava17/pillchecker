import 'package:pillchecker/models/pill_search_item.dart';

/// Bundled, on-device medication names for search when there is no network
/// or before RxNorm results load. No internet required.
const kOfflineMedicationSuggestions = <PillSearchItem>[
  PillSearchItem(
    name: 'Paracetamol',
    suggestedTimesPerDay: 3,
    info:
        'Pain and fever relief. Follow the dose on your package or label. Do not exceed the maximum daily amount.',
  ),
  PillSearchItem(
    name: 'Acetaminophen',
    suggestedTimesPerDay: 3,
    info:
        'Same type of medicine as paracetamol (US name). Check your label for strength and max daily dose.',
  ),
  PillSearchItem(
    name: 'Ibuprofen',
    suggestedTimesPerDay: 2,
    info:
        'Anti-inflammatory pain reliever. Take with food if it upsets your stomach unless your clinician said otherwise.',
  ),
  PillSearchItem(
    name: 'Aspirin',
    suggestedTimesPerDay: 1,
    info:
        'Pain relief and blood thinner in some doses. Ask your clinician before use if you have bleeding risk.',
  ),
  PillSearchItem(
    name: 'Amoxicillin',
    suggestedTimesPerDay: 3,
    info: 'Antibiotic — finish the course as prescribed. Take with food if stomach upset.',
  ),
  PillSearchItem(
    name: 'Metformin',
    suggestedTimesPerDay: 2,
    info: 'Common diabetes medicine — often taken with meals. Your clinician sets the dose.',
  ),
  PillSearchItem(
    name: 'Atorvastatin',
    suggestedTimesPerDay: 1,
    info: 'Cholesterol medicine — usually once daily. Follow your prescription label.',
  ),
  PillSearchItem(
    name: 'Omeprazole',
    suggestedTimesPerDay: 1,
    info: 'Reduces stomach acid — often before breakfast. Use as directed on your label.',
  ),
  PillSearchItem(
    name: 'Levothyroxine',
    suggestedTimesPerDay: 1,
    info: 'Thyroid hormone — usually on an empty stomach; spacing from other meds matters.',
  ),
  PillSearchItem(
    name: 'Lisinopril',
    suggestedTimesPerDay: 1,
    info: 'Blood pressure medicine. Your clinician may monitor kidney function and potassium.',
  ),
  PillSearchItem(
    name: 'Amlodipine',
    suggestedTimesPerDay: 1,
    info: 'Blood pressure / heart medicine — often once daily. Swelling ankles can be a side effect.',
  ),
  PillSearchItem(
    name: 'Metoprolol',
    suggestedTimesPerDay: 2,
    info: 'Heart rate / blood pressure medicine. Do not stop suddenly unless your clinician says so.',
  ),
  PillSearchItem(
    name: 'Sertraline',
    suggestedTimesPerDay: 1,
    info: 'Antidepressant — may take weeks to feel full effect. Do not stop abruptly without advice.',
  ),
  PillSearchItem(
    name: 'Escitalopram',
    suggestedTimesPerDay: 1,
    info: 'Antidepressant — follow your prescribed dose; do not change dose without your clinician.',
  ),
  PillSearchItem(
    name: 'Gabapentin',
    suggestedTimesPerDay: 3,
    info: 'Nerve pain / seizure medicine — dose is often adjusted gradually. Take as prescribed.',
  ),
  PillSearchItem(
    name: 'Pantoprazole',
    suggestedTimesPerDay: 1,
    info: 'Stomach acid reducer — usually before a meal. Use as on your label.',
  ),
  PillSearchItem(
    name: 'Simvastatin',
    suggestedTimesPerDay: 1,
    info: 'Cholesterol medicine — often in the evening. Grapefruit can interact — ask your pharmacist.',
  ),
  PillSearchItem(
    name: 'Losartan',
    suggestedTimesPerDay: 1,
    info: 'Blood pressure medicine. Stay hydrated; report dizziness to your clinician.',
  ),
  PillSearchItem(
    name: 'Hydrochlorothiazide',
    suggestedTimesPerDay: 1,
    info: 'Water pill for blood pressure — may increase urination. Monitor with your clinician.',
  ),
  PillSearchItem(
    name: 'Furosemide',
    suggestedTimesPerDay: 1,
    info: 'Strong diuretic — frequent urination expected. Potassium may need monitoring.',
  ),
  PillSearchItem(
    name: 'Warfarin',
    suggestedTimesPerDay: 1,
    info: 'Blood thinner — dosing is individualized; regular INR checks if prescribed.',
  ),
  PillSearchItem(
    name: 'Clopidogrel',
    suggestedTimesPerDay: 1,
    info: 'Antiplatelet medicine — bleeding risk; tell dentists and surgeons you take it.',
  ),
  PillSearchItem(
    name: 'Albuterol',
    suggestedTimesPerDay: 3,
    info: 'Rescue inhaler for wheeze — use as directed; seek urgent care if breathing is severe.',
  ),
  PillSearchItem(
    name: 'Fluticasone',
    suggestedTimesPerDay: 2,
    info: 'Inhaled steroid for asthma — rinse mouth after use to reduce thrush risk.',
  ),
  PillSearchItem(
    name: 'Montelukast',
    suggestedTimesPerDay: 1,
    info: 'Allergy / asthma tablet — usually evening. Report mood changes to your clinician.',
  ),
  PillSearchItem(
    name: 'Cetirizine',
    suggestedTimesPerDay: 1,
    info: 'Antihistamine for allergies — may cause drowsiness in some people.',
  ),
  PillSearchItem(
    name: 'Loratadine',
    suggestedTimesPerDay: 1,
    info: 'Non-drowsy antihistamine for allergies — follow package directions.',
  ),
  PillSearchItem(
    name: 'Diclofenac',
    suggestedTimesPerDay: 2,
    info: 'NSAID gel or tablet — avoid combining with other NSAIDs unless advised.',
  ),
  PillSearchItem(
    name: 'Naproxen',
    suggestedTimesPerDay: 2,
    info: 'NSAID for pain — take with food; ask about stomach and kidney risk.',
  ),
  PillSearchItem(
    name: 'Prednisone',
    suggestedTimesPerDay: 1,
    info: 'Steroid — do not stop suddenly; take exactly as your clinician prescribed.',
  ),
  PillSearchItem(
    name: 'Insulin glargine',
    suggestedTimesPerDay: 1,
    info: 'Long-acting insulin — dosing is individual; rotate injection sites.',
  ),
  PillSearchItem(
    name: 'Glimepiride',
    suggestedTimesPerDay: 1,
    info: 'Lowers blood sugar — hypoglycemia risk; eat consistently as advised.',
  ),
  PillSearchItem(
    name: 'Empagliflozin',
    suggestedTimesPerDay: 1,
    info: 'Diabetes medicine — increased urination; stay hydrated; foot care matters.',
  ),
  PillSearchItem(
    name: 'Tamsulosin',
    suggestedTimesPerDay: 1,
    info: 'Prostate / urinary symptoms — often taken after the same meal daily.',
  ),
  PillSearchItem(
    name: 'Finasteride',
    suggestedTimesPerDay: 1,
    info: 'Prostate / hair — takes months for full effect; women who are pregnant should not handle crushed tablets.',
  ),
  PillSearchItem(
    name: 'Melatonin',
    suggestedTimesPerDay: 1,
    info: 'Sleep aid supplement — start low; can cause morning grogginess.',
  ),
  PillSearchItem(
    name: 'Vitamin D3',
    suggestedTimesPerDay: 1,
    info: 'Supplement — dose varies; many people take once daily with food.',
  ),
  PillSearchItem(
    name: 'Vitamin B12',
    suggestedTimesPerDay: 1,
    info: 'Supplement — follow your clinician if you have deficiency.',
  ),
  PillSearchItem(
    name: 'Iron supplement',
    suggestedTimesPerDay: 1,
    info: 'Can cause constipation — take as directed; some forms are taken on empty stomach.',
  ),
  PillSearchItem(
    name: 'Calcium carbonate',
    suggestedTimesPerDay: 2,
    info: 'Bone health / antacid use — spacing from other medicines may matter.',
  ),
  PillSearchItem(
    name: 'Magnesium',
    suggestedTimesPerDay: 1,
    info: 'Supplement — can affect bowels; kidney disease needs caution.',
  ),
  PillSearchItem(
    name: 'Omega-3',
    suggestedTimesPerDay: 1,
    info: 'Fish oil supplement — may interact with blood thinners at high doses.',
  ),
  PillSearchItem(
    name: 'Azithromycin',
    suggestedTimesPerDay: 1,
    info: 'Antibiotic — often a short course; complete as prescribed.',
  ),
  PillSearchItem(
    name: 'Ciprofloxacin',
    suggestedTimesPerDay: 2,
    info: 'Antibiotic — avoid dairy timing conflicts; stay hydrated.',
  ),
  PillSearchItem(
    name: 'Doxycycline',
    suggestedTimesPerDay: 2,
    info: 'Antibiotic — sun sensitivity; take with plenty of water.',
  ),
  PillSearchItem(
    name: 'Fluconazole',
    suggestedTimesPerDay: 1,
    info: 'Antifungal — can interact with many medicines; pharmacist review helps.',
  ),
  PillSearchItem(
    name: 'Acyclovir',
    suggestedTimesPerDay: 3,
    info: 'Antiviral — dosing depends on condition; follow your prescription.',
  ),
  PillSearchItem(
    name: 'Sumatriptan',
    suggestedTimesPerDay: 2,
    info: 'Migraine medicine — not for certain heart conditions; use as directed.',
  ),
  PillSearchItem(
    name: 'Ondansetron',
    suggestedTimesPerDay: 3,
    info: 'Nausea medicine — constipation can occur; follow prescribed limits.',
  ),
  PillSearchItem(
    name: 'Tramadol',
    suggestedTimesPerDay: 3,
    info: 'Pain medicine — drowsiness risk; avoid alcohol; use only as prescribed.',
  ),
  PillSearchItem(
    name: 'Codeine',
    suggestedTimesPerDay: 3,
    info: 'Opioid pain medicine — sedation and dependence risk; use strictly as directed.',
  ),
  PillSearchItem(
    name: 'Morphine',
    suggestedTimesPerDay: 3,
    info: 'Strong opioid — only as prescribed; never share; risk of breathing problems.',
  ),
  PillSearchItem(
    name: 'Oxycodone',
    suggestedTimesPerDay: 3,
    info: 'Opioid — high risk medicine; take exactly as prescribed.',
  ),
  PillSearchItem(
    name: 'Hydrocodone',
    suggestedTimesPerDay: 3,
    info: 'Opioid combination products — sedation risk; follow label closely.',
  ),
  PillSearchItem(
    name: 'Baclofen',
    suggestedTimesPerDay: 3,
    info: 'Muscle relaxer — drowsiness; do not stop suddenly without medical advice.',
  ),
  PillSearchItem(
    name: 'Cyclobenzaprine',
    suggestedTimesPerDay: 2,
    info: 'Muscle relaxer — sedation; short-term use common.',
  ),
  PillSearchItem(
    name: 'Allopurinol',
    suggestedTimesPerDay: 1,
    info: 'Gout medicine — flare can occur when starting; hydration helps.',
  ),
  PillSearchItem(
    name: 'Colchicine',
    suggestedTimesPerDay: 3,
    info: 'Gout flare — dosing varies; kidney and drug interactions matter.',
  ),
  PillSearchItem(
    name: 'Methotrexate',
    suggestedTimesPerDay: 1,
    info: 'Immune/arthritis medicine — weekly dosing common; folic acid often paired.',
  ),
  PillSearchItem(
    name: 'Adalimumab',
    suggestedTimesPerDay: 1,
    info: 'Injectable biologic — special handling; clinician-directed schedule.',
  ),
  PillSearchItem(
    name: 'Insulin aspart',
    suggestedTimesPerDay: 3,
    info: 'Mealtime insulin — carb counting and timing with meals.',
  ),
  PillSearchItem(
    name: 'Glyburide',
    suggestedTimesPerDay: 2,
    info: 'Lowers blood sugar — hypoglycemia risk; eat regularly.',
  ),
  PillSearchItem(
    name: 'Sitagliptin',
    suggestedTimesPerDay: 1,
    info: 'Diabetes tablet — usually once daily; report unusual joint pain.',
  ),
  PillSearchItem(
    name: 'Duloxetine',
    suggestedTimesPerDay: 1,
    info: 'For pain or mood — do not stop suddenly; may affect blood pressure.',
  ),
  PillSearchItem(
    name: 'Venlafaxine',
    suggestedTimesPerDay: 2,
    info: 'Antidepressant — withdrawal can occur if stopped abruptly.',
  ),
  PillSearchItem(
    name: 'Quetiapine',
    suggestedTimesPerDay: 2,
    info: 'Antipsychotic / mood — sedation and metabolic monitoring may apply.',
  ),
  PillSearchItem(
    name: 'Risperidone',
    suggestedTimesPerDay: 1,
    info: 'Antipsychotic — movement side effects possible; regular follow-up.',
  ),
  PillSearchItem(
    name: 'Alprazolam',
    suggestedTimesPerDay: 2,
    info: 'Benzodiazepine — dependence risk; use short-term as prescribed.',
  ),
  PillSearchItem(
    name: 'Lorazepam',
    suggestedTimesPerDay: 2,
    info: 'Sedative — drowsiness; avoid alcohol; taper only with clinician guidance.',
  ),
  PillSearchItem(
    name: 'Zolpidem',
    suggestedTimesPerDay: 1,
    info: 'Sleep medicine — next-day impairment risk; only before a full night in bed.',
  ),
  PillSearchItem(
    name: 'Trazodone',
    suggestedTimesPerDay: 1,
    info: 'Often used for sleep — dizziness possible; follow your dose.',
  ),
  PillSearchItem(
    name: 'Spironolactone',
    suggestedTimesPerDay: 1,
    info: 'Diuretic / hormone effects — potassium monitoring may be needed.',
  ),
  PillSearchItem(
    name: 'Carvedilol',
    suggestedTimesPerDay: 2,
    info: 'Beta blocker — take with food; do not stop suddenly.',
  ),
  PillSearchItem(
    name: 'Digoxin',
    suggestedTimesPerDay: 1,
    info: 'Heart medicine — narrow therapeutic window; regular monitoring.',
  ),
  PillSearchItem(
    name: 'Apixaban',
    suggestedTimesPerDay: 2,
    info: 'Blood thinner — bleeding precautions; timing matters.',
  ),
  PillSearchItem(
    name: 'Rivaroxaban',
    suggestedTimesPerDay: 1,
    info: 'Blood thinner — take with food for some doses; bleeding risk.',
  ),
  PillSearchItem(
    name: 'Eliquis',
    suggestedTimesPerDay: 2,
    info: 'Brand blood thinner (apixaban) — follow your prescription exactly.',
  ),
  PillSearchItem(
    name: 'Xarelto',
    suggestedTimesPerDay: 1,
    info: 'Brand blood thinner (rivaroxaban) — food instructions depend on dose.',
  ),
];
