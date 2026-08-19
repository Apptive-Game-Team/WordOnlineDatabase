UPDATE parameter_values pv
SET value = pv.value * 10
FROM parameters p
WHERE pv.parameter_id = p.id
  AND (p.name = 'hp' OR p.name LIKE '%damage%');
