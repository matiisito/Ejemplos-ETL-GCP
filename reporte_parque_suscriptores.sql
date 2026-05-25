-- ============================================================
-- CONFIGURACIÓN — Reemplaza estos valores antes de ejecutar
-- ============================================================
--   PROJECT_ID          → tu ID de proyecto GCP        Ej: 'mi-proyecto-gcp'
--   DATASET_ID          → tu dataset en BigQuery        Ej: 'mi_dataset'
--   TABLA_PARQUE        → tabla de parque suscriptores  Ej: 'Parque_Suscriptores'
--   TABLA_TRX           → tabla de transacciones        Ej: 'Parque_Suscriptores_Trx'
--   FX_PLANTILLA        → función plantilla de correo   Ej: 'Fx_PlantillaCorreo'
--   URL_LOOKER          → URL del reporte en Looker     Ej: 'https://lookerstudio.google.com/reporting/...'
--   EMAIL_REMITENTE     → correo del equipo             Ej: 'equipo@tudominio.com'
-- ============================================================

BEGIN

DECLARE titulo STRING;
DECLARE boton STRING;
DECLARE Body_HTML STRING;
DECLARE grafico_html STRING;
DECLARE tabla_sva_html STRING;
DECLARE tabla_smsp_html STRING;
DECLARE tabla_arpu_sva_html STRING;
DECLARE tabla_arpu_smsp_html STRING;

-- ============================================================
-- TABLA BASE PARQUE
-- ============================================================
CREATE TEMP TABLE PARQUE AS
SELECT
  PERIODO,
  SUM(CASE WHEN TIPO = 'SMSP' THEN Q_LINEAS_SUSCRITAS ELSE 0 END) AS SMS,
  SUM(CASE WHEN TIPO = 'SVA'  THEN Q_LINEAS_SUSCRITAS ELSE 0 END) AS SVA
FROM `TU_PROJECT_ID.TU_DATASET_ID.NOMBRE_TABLA_PARQUE`
WHERE PERIODO >= CAST(FORMAT_DATE('%Y%m', DATE_SUB(CURRENT_DATE(), INTERVAL 7 MONTH)) AS INT)
GROUP BY PERIODO;

-- ============================================================
-- TABLA SVA POR TIPO DETALLADO
-- ============================================================
CREATE TEMP TABLE PARQUE_SVA AS
SELECT
  SVA_SMS,
  PERIODO,
  SUM(Q_LINEAS_SUSCRITAS) AS Q
FROM `TU_PROJECT_ID.TU_DATASET_ID.NOMBRE_TABLA_PARQUE`
WHERE PERIODO >= CAST(FORMAT_DATE('%Y%m', DATE_SUB(CURRENT_DATE(), INTERVAL 7 MONTH)) AS INT)
  AND TIPO = 'SVA'
GROUP BY 1, 2;

-- ============================================================
-- TABLA SMSP TOP 10
-- ============================================================
CREATE TEMP TABLE PARQUE_SMSP AS
SELECT
  SVA_SMS,
  PERIODO,
  SUM(Q_LINEAS_SUSCRITAS) AS Q
FROM `TU_PROJECT_ID.TU_DATASET_ID.NOMBRE_TABLA_PARQUE`
WHERE PERIODO >= CAST(FORMAT_DATE('%Y%m', DATE_SUB(CURRENT_DATE(), INTERVAL 7 MONTH)) AS INT)
  AND TIPO = 'SMSP'
GROUP BY 1, 2;

-- ============================================================
-- TABLA ARPU SVA
-- ============================================================
CREATE TEMP TABLE PARQUE_ARPU_SVA AS
SELECT
  SVA_SMS,
  PERIODO,
  ROUND(SUM(Q_TRANSACCIONES * MONTO_NETO) / SUM(Q_TRANSACCIONES), 0) AS ARPU
FROM `TU_PROJECT_ID.TU_DATASET_ID.NOMBRE_TABLA_TRX`
WHERE PERIODO >= CAST(FORMAT_DATE('%Y%m', DATE_SUB(CURRENT_DATE(), INTERVAL 7 MONTH)) AS INT)
  AND TIPO = 'SVA'
GROUP BY 1, 2;

-- ============================================================
-- TABLA ARPU SMSP
-- ============================================================
CREATE TEMP TABLE PARQUE_ARPU_SMSP AS
SELECT
  SVA_SMS,
  PERIODO,
  ROUND(SUM(Q_TRANSACCIONES * MONTO_NETO) / NULLIF(SUM(Q_TRANSACCIONES), 0), 0) AS ARPU
FROM `TU_PROJECT_ID.TU_DATASET_ID.NOMBRE_TABLA_TRX`
WHERE PERIODO >= CAST(FORMAT_DATE('%Y%m', DATE_SUB(CURRENT_DATE(), INTERVAL 7 MONTH)) AS INT)
  AND TIPO = 'SMSP'
GROUP BY SVA_SMS, PERIODO
QUALIFY ROW_NUMBER() OVER (PARTITION BY SVA_SMS, PERIODO ORDER BY PERIODO) = 1;

-- ============================================================
-- GRÁFICO DE BARRAS CSS (email-safe, sin JS)
-- ============================================================
SET grafico_html = (
  SELECT CONCAT(

    '<table border="0" cellpadding="0" cellspacing="0" width="100%" ',
    'style="background:#2d1b4e;border-radius:10px;padding:20px;">',

    '<tr><td colspan="99" style="padding-bottom:12px;">',
    '<p style="font-family:Arial;font-size:13px;font-weight:bold;color:#d8b4fe;margin:0;">',
    '📊 Evolución Parque Suscriptores — Últimos 8 meses</p>',
    '</td></tr>',

    '<tr>',
    (
      SELECT STRING_AGG(
        CONCAT(
          '<td valign="bottom" align="center" style="padding:0 6px;vertical-align:bottom;">',
          '<div style="font-family:Arial;font-size:11px;color:#f0abfc;',
          'font-weight:bold;margin-bottom:4px;text-align:center;">',
          CONCAT(CAST(CAST(ROUND((SMS+SVA)/1000) AS INT64) AS STRING), 'k'),
          '</div>',
          '<div style="width:52px;background:#c484fc;height:',
          CAST(CAST(ROUND(SVA / 2000) AS INT64) AS STRING),
          'px;border-radius:4px 4px 0 0;text-align:center;padding-top:3px;">',
          '<span style="font-family:Arial;font-size:9px;color:#1a0a2e;font-weight:bold;">',
          CONCAT(CAST(CAST(ROUND(SVA/1000) AS INT64) AS STRING), 'k'),
          '</span></div>',
          '<div style="width:52px;background:#7c3aed;height:',
          CAST(CAST(ROUND(SMS / 2000) AS INT64) AS STRING),
          'px;text-align:center;padding-top:3px;">',
          '<span style="font-family:Arial;font-size:9px;color:#ffffff;font-weight:bold;">',
          CONCAT(CAST(CAST(ROUND(SMS/1000) AS INT64) AS STRING), 'k'),
          '</span></div>',
          '<div style="width:52px;height:2px;background:#5a3a8e;"></div>',
          '<div style="font-family:Arial;font-size:10px;color:#c4b5fd;',
          'margin-top:5px;text-align:center;">',
          CAST(PERIODO AS STRING),
          '</div>',
          '</td>'
        ),
        ''
        ORDER BY PERIODO ASC
      )
      FROM PARQUE
    ),
    '</tr>',

    '<tr><td colspan="99" style="padding-top:14px;border-top:1px solid #4a2e7e;text-align:center;">',
    '<span style="display:inline-block;margin-right:14px;">',
    '<span style="display:inline-block;width:10px;height:10px;background:#7c3aed;',
    'vertical-align:middle;margin-right:4px;"></span>',
    '<span style="font-family:Arial;font-size:11px;color:#c4b5fd;">SMS</span></span>',
    '<span style="display:inline-block;margin-right:14px;">',
    '<span style="display:inline-block;width:10px;height:10px;background:#c484fc;',
    'vertical-align:middle;margin-right:4px;"></span>',
    '<span style="font-family:Arial;font-size:11px;color:#c4b5fd;">SVA</span></span>',
    '<span style="font-family:Arial;font-size:11px;color:#f0abfc;font-weight:bold;">',
    '| Total = SMS + SVA</span>',
    '</td></tr>',

    '</table>'
  )
  FROM (SELECT 1)
);

-- ============================================================
-- TABLA SVA POR TIPO (filas=SVA_SMS, columnas=PERIODO)
-- ============================================================
SET tabla_sva_html = (
  WITH
  periodos AS (
    SELECT DISTINCT PERIODO FROM PARQUE_SVA ORDER BY PERIODO ASC
  ),
  tipos AS (
    SELECT DISTINCT SVA_SMS FROM PARQUE_SVA ORDER BY SVA_SMS
  ),
  header AS (
    SELECT CONCAT(
      '<tr style="background:#4d008c;color:#ffffff;text-align:center;">',
      '<th style="font-family:Arial;font-size:12px;padding:6px;text-align:left;">SVA</th>',
      STRING_AGG(
        CONCAT('<th style="font-family:Arial;font-size:12px;padding:6px;">', CAST(PERIODO AS STRING), '</th>'),
        '' ORDER BY PERIODO ASC
      ),
      '<th style="font-family:Arial;font-size:12px;padding:6px;">Total</th>',
      '</tr>'
    ) AS html
    FROM periodos
  ),
  filas AS (
    SELECT
      t.SVA_SMS,
      ROW_NUMBER() OVER (ORDER BY t.SVA_SMS) AS rn,
      STRING_AGG(
        CONCAT(
          '<td style="font-family:Arial;font-size:11px;text-align:right;padding:5px;">',
          IFNULL(
            CONCAT('', REVERSE(ARRAY_TO_STRING(ARRAY(
              SELECT REGEXP_EXTRACT(x, r'\d{1,3}')
              FROM UNNEST(REGEXP_EXTRACT_ALL(REVERSE(CAST(CAST(IFNULL(s.Q, 0) AS INT64) AS STRING)), r'\d{1,3}')) AS x
            ), '.'))),
            '-'
          ),
          '</td>'
        ),
        '' ORDER BY p.PERIODO ASC
      ) AS celdas,
      SUM(IFNULL(s.Q, 0)) AS total_fila
    FROM tipos t
    CROSS JOIN periodos p
    LEFT JOIN PARQUE_SVA s ON s.SVA_SMS = t.SVA_SMS AND s.PERIODO = p.PERIODO
    GROUP BY t.SVA_SMS
  ),
  totales AS (
    SELECT
      PERIODO,
      SUM(Q) AS total_periodo,
      SUM(SUM(Q)) OVER () AS gran_total
    FROM PARQUE_SVA
    GROUP BY PERIODO
  ),
  totales_html AS (
    SELECT CONCAT(
      '<tr style="background:#4d008c;color:#ffffff;font-weight:bold;">',
      '<td style="font-family:Arial;font-size:12px;padding:6px;">Total</td>',
      STRING_AGG(
        CONCAT(
          '<td style="font-family:Arial;font-size:11px;text-align:right;padding:5px;">',
          CONCAT('', REVERSE(ARRAY_TO_STRING(ARRAY(
            SELECT REGEXP_EXTRACT(x, r'\d{1,3}')
            FROM UNNEST(REGEXP_EXTRACT_ALL(REVERSE(CAST(total_periodo AS STRING)), r'\d{1,3}')) AS x
          ), '.'))),
          '</td>'
        ),
        '' ORDER BY PERIODO ASC
      ),
      '<td style="font-family:Arial;font-size:11px;text-align:right;padding:5px;">',
      (
        SELECT CONCAT('', REVERSE(ARRAY_TO_STRING(ARRAY(
          SELECT REGEXP_EXTRACT(x, r'\d{1,3}')
          FROM UNNEST(REGEXP_EXTRACT_ALL(REVERSE(CAST(gt.gran_total AS STRING)), r'\d{1,3}')) AS x
        ), '.')))
        FROM (SELECT gran_total FROM totales LIMIT 1) gt
      ),
      '</td>',
      '</tr>'
    ) AS html
    FROM totales
  )
  SELECT CONCAT(
    '<p style="font-family:Arial;font-size:13px;font-weight:bold;color:#4d008c;margin:20px 0 8px;">',
    'Detalle SVA por Tipo</p>',
    '<table width="100%" cellpadding="5" cellspacing="0" ',
    'style="font-family:Arial;font-size:12px;border-collapse:collapse;border:1px solid #cccccc;">',
    (SELECT html FROM header),
    (
      SELECT STRING_AGG(
        CONCAT(
          '<tr style="background:', IF(MOD(rn,2)=0,'#f3f3f3','#ffffff'), ';">',
          '<td style="font-family:Arial;font-size:11px;padding:5px;text-align:left;',
          'color:#4d008c;font-weight:bold;">', SVA_SMS, '</td>',
          celdas,
          '<td style="font-family:Arial;font-size:11px;text-align:right;padding:5px;',
          'color:#7c3aed;font-weight:bold;">',
          CONCAT('', REVERSE(ARRAY_TO_STRING(ARRAY(
            SELECT REGEXP_EXTRACT(x, r'\d{1,3}')
            FROM UNNEST(REGEXP_EXTRACT_ALL(REVERSE(CAST(CAST(total_fila AS INT64) AS STRING)), r'\d{1,3}')) AS x
          ), '.'))),
          '</td>',
          '</tr>'
        ),
        '' ORDER BY rn
      )
      FROM filas
    ),
    (SELECT html FROM totales_html),
    '</table>'
  )
);

-- ============================================================
-- TABLA SMSP TOP 10 (filas=SVA_SMS, columnas=PERIODO)
-- ============================================================
SET tabla_smsp_html = (
  WITH
  top10 AS (
    SELECT SVA_SMS, SUM(Q) AS total_general
    FROM PARQUE_SMSP
    GROUP BY SVA_SMS
    ORDER BY total_general DESC
    LIMIT 10
  ),
  periodos AS (
    SELECT DISTINCT PERIODO FROM PARQUE_SMSP ORDER BY PERIODO ASC
  ),
  tipos AS (
    SELECT SVA_SMS, total_general,
    ROW_NUMBER() OVER (ORDER BY total_general DESC) AS rn
    FROM top10
  ),
  header AS (
    SELECT CONCAT(
      '<tr style="background:#4d008c;color:#ffffff;text-align:center;">',
      '<th style="font-family:Arial;font-size:12px;padding:6px;text-align:left;">#</th>',
      '<th style="font-family:Arial;font-size:12px;padding:6px;text-align:left;">SMSP</th>',
      STRING_AGG(
        CONCAT('<th style="font-family:Arial;font-size:12px;padding:6px;">', CAST(PERIODO AS STRING), '</th>'),
        '' ORDER BY PERIODO ASC
      ),
      '<th style="font-family:Arial;font-size:12px;padding:6px;">Total</th>',
      '</tr>'
    ) AS html
    FROM periodos
  ),
  filas AS (
    SELECT
      t.SVA_SMS, t.rn, t.total_general,
      STRING_AGG(
        CONCAT(
          '<td style="font-family:Arial;font-size:11px;text-align:right;padding:5px;">',
          IFNULL(
            CONCAT('', REVERSE(ARRAY_TO_STRING(ARRAY(
              SELECT REGEXP_EXTRACT(x, r'\d{1,3}')
              FROM UNNEST(REGEXP_EXTRACT_ALL(REVERSE(CAST(CAST(IFNULL(s.Q, 0) AS INT64) AS STRING)), r'\d{1,3}')) AS x
            ), '.'))),
            '-'
          ),
          '</td>'
        ),
        '' ORDER BY p.PERIODO ASC
      ) AS celdas
    FROM tipos t
    CROSS JOIN periodos p
    LEFT JOIN PARQUE_SMSP s ON s.SVA_SMS = t.SVA_SMS AND s.PERIODO = p.PERIODO
    GROUP BY t.SVA_SMS, t.rn, t.total_general
  ),
  totales AS (
    SELECT
      PERIODO,
      SUM(Q) AS total_periodo,
      SUM(SUM(Q)) OVER () AS gran_total
    FROM PARQUE_SMSP
    WHERE SVA_SMS IN (SELECT SVA_SMS FROM top10)
    GROUP BY PERIODO
  ),
  totales_html AS (
    SELECT CONCAT(
      '<tr style="background:#4d008c;color:#ffffff;font-weight:bold;">',
      '<td style="font-family:Arial;font-size:12px;padding:6px;" colspan="2">Total Top 10</td>',
      STRING_AGG(
        CONCAT(
          '<td style="font-family:Arial;font-size:11px;text-align:right;padding:5px;">',
          CONCAT('', REVERSE(ARRAY_TO_STRING(ARRAY(
            SELECT REGEXP_EXTRACT(x, r'\d{1,3}')
            FROM UNNEST(REGEXP_EXTRACT_ALL(REVERSE(CAST(total_periodo AS STRING)), r'\d{1,3}')) AS x
          ), '.'))),
          '</td>'
        ),
        '' ORDER BY PERIODO ASC
      ),
      '<td style="font-family:Arial;font-size:11px;text-align:right;padding:5px;">',
      (
        SELECT CONCAT('', REVERSE(ARRAY_TO_STRING(ARRAY(
          SELECT REGEXP_EXTRACT(x, r'\d{1,3}')
          FROM UNNEST(REGEXP_EXTRACT_ALL(REVERSE(CAST(gt.gran_total AS STRING)), r'\d{1,3}')) AS x
        ), '.')))
        FROM (SELECT gran_total FROM totales LIMIT 1) gt
      ),
      '</td>',
      '</tr>'
    ) AS html
    FROM totales
  )
  SELECT CONCAT(
    '<p style="font-family:Arial;font-size:13px;font-weight:bold;color:#4d008c;margin:20px 0 8px;">',
    'Top 10 Suscripciones SMSP</p>',
    '<table width="100%" cellpadding="5" cellspacing="0" ',
    'style="font-family:Arial;font-size:12px;border-collapse:collapse;border:1px solid #cccccc;">',
    (SELECT html FROM header),
    (
      SELECT STRING_AGG(
        CONCAT(
          '<tr style="background:', IF(MOD(rn,2)=0,'#f3f3f3','#ffffff'), ';">',
          '<td style="font-family:Arial;font-size:11px;padding:5px;text-align:center;',
          'color:#7c3aed;font-weight:bold;">', CAST(rn AS STRING), '</td>',
          '<td style="font-family:Arial;font-size:11px;padding:5px;text-align:left;',
          'color:#4d008c;font-weight:bold;">', SVA_SMS, '</td>',
          celdas,
          '<td style="font-family:Arial;font-size:11px;text-align:right;padding:5px;',
          'color:#7c3aed;font-weight:bold;">',
          CONCAT('', REVERSE(ARRAY_TO_STRING(ARRAY(
            SELECT REGEXP_EXTRACT(x, r'\d{1,3}')
            FROM UNNEST(REGEXP_EXTRACT_ALL(REVERSE(CAST(CAST(total_general AS INT64) AS STRING)), r'\d{1,3}')) AS x
          ), '.'))),
          '</td>',
          '</tr>'
        ),
        '' ORDER BY rn
      )
      FROM filas
    ),
    (SELECT html FROM totales_html),
    '</table>'
  )
);

-- ============================================================
-- TABLA ARPU SVA (filas=SVA_SMS, columnas=PERIODO)
-- ============================================================
SET tabla_arpu_sva_html = (
  WITH
  periodos AS (
    SELECT DISTINCT PERIODO FROM PARQUE_ARPU_SVA ORDER BY PERIODO ASC
  ),
  tipos AS (
    SELECT SVA_SMS, ROW_NUMBER() OVER (ORDER BY SVA_SMS) AS rn
    FROM (SELECT DISTINCT SVA_SMS FROM PARQUE_ARPU_SVA)
  ),
  header AS (
    SELECT CONCAT(
      '<tr style="background:#4d008c;color:#ffffff;text-align:center;">',
      '<th style="font-family:Arial;font-size:12px;padding:6px;text-align:left;">SVA</th>',
      STRING_AGG(
        CONCAT('<th style="font-family:Arial;font-size:12px;padding:6px;">', CAST(PERIODO AS STRING), '</th>'),
        '' ORDER BY PERIODO ASC
      ),
      '</tr>'
    ) AS html
    FROM periodos
  ),
  filas AS (
    SELECT
      t.SVA_SMS, t.rn,
      STRING_AGG(
        CONCAT(
          '<td style="font-family:Arial;font-size:11px;text-align:right;padding:5px;">',
          IFNULL(
            CONCAT('$ ', REVERSE(ARRAY_TO_STRING(ARRAY(
              SELECT REGEXP_EXTRACT(x, r'\d{1,3}')
              FROM UNNEST(REGEXP_EXTRACT_ALL(REVERSE(CAST(CAST(IFNULL(s.ARPU, 0) AS INT64) AS STRING)), r'\d{1,3}')) AS x
            ), '.'))),
            '-'
          ),
          '</td>'
        ),
        '' ORDER BY p.PERIODO ASC
      ) AS celdas
    FROM tipos t
    CROSS JOIN periodos p
    LEFT JOIN PARQUE_ARPU_SVA s ON s.SVA_SMS = t.SVA_SMS AND s.PERIODO = p.PERIODO
    GROUP BY t.SVA_SMS, t.rn
  ),
  totales AS (
    SELECT
      PERIODO,
      ROUND(SUM(Q_TRANSACCIONES * MONTO_NETO) / SUM(Q_TRANSACCIONES), 0) AS arpu_periodo
    FROM `TU_PROJECT_ID.TU_DATASET_ID.NOMBRE_TABLA_TRX`
    WHERE PERIODO >= CAST(FORMAT_DATE('%Y%m', DATE_SUB(CURRENT_DATE(), INTERVAL 7 MONTH)) AS INT)
      AND TIPO = 'SVA'
    GROUP BY PERIODO
  ),
  totales_html AS (
    SELECT CONCAT(
      '<tr style="background:#4d008c;color:#ffffff;font-weight:bold;">',
      '<td style="font-family:Arial;font-size:12px;padding:6px;">Ticket promedio</td>',
      STRING_AGG(
        CONCAT(
          '<td style="font-family:Arial;font-size:11px;text-align:right;padding:5px;">',
          CONCAT('$ ', REVERSE(ARRAY_TO_STRING(ARRAY(
            SELECT REGEXP_EXTRACT(x, r'\d{1,3}')
            FROM UNNEST(REGEXP_EXTRACT_ALL(REVERSE(CAST(CAST(arpu_periodo AS INT64) AS STRING)), r'\d{1,3}')) AS x
          ), '.'))),
          '</td>'
        ),
        '' ORDER BY PERIODO ASC
      ),
      '</tr>'
    ) AS html
    FROM totales
  )
  SELECT CONCAT(
    '<p style="font-family:Arial;font-size:13px;font-weight:bold;color:#4d008c;margin:20px 0 8px;">',
    'Ticket promedio por Tipo</p>',
    '<table width="100%" cellpadding="5" cellspacing="0" ',
    'style="font-family:Arial;font-size:12px;border-collapse:collapse;border:1px solid #cccccc;">',
    (SELECT html FROM header),
    (
      SELECT STRING_AGG(
        CONCAT(
          '<tr style="background:', IF(MOD(rn,2)=0,'#f3f3f3','#ffffff'), ';">',
          '<td style="font-family:Arial;font-size:11px;padding:5px;text-align:left;',
          'color:#4d008c;font-weight:bold;">', SVA_SMS, '</td>',
          celdas,
          '</tr>'
        ),
        '' ORDER BY rn
      )
      FROM filas
    ),
    (SELECT html FROM totales_html),
    '</table>'
  )
);

-- ============================================================
-- TABLA ARPU SMSP TOP 10 (filas=SVA_SMS, columnas=PERIODO)
-- ============================================================
SET tabla_arpu_smsp_html = (
  WITH
  top10 AS (
    SELECT SVA_SMS, ROUND(AVG(ARPU), 0) AS arpu_promedio
    FROM PARQUE_ARPU_SMSP
    GROUP BY SVA_SMS
    ORDER BY arpu_promedio DESC
    LIMIT 10
  ),
  periodos AS (
    SELECT DISTINCT PERIODO FROM PARQUE_ARPU_SMSP ORDER BY PERIODO ASC
  ),
  tipos AS (
    SELECT SVA_SMS, arpu_promedio,
    ROW_NUMBER() OVER (ORDER BY arpu_promedio DESC) AS rn
    FROM top10
  ),
  header AS (
    SELECT CONCAT(
      '<tr style="background:#4d008c;color:#ffffff;text-align:center;">',
      '<th style="font-family:Arial;font-size:12px;padding:6px;text-align:left;">#</th>',
      '<th style="font-family:Arial;font-size:12px;padding:6px;text-align:left;">SMSP</th>',
      STRING_AGG(
        CONCAT('<th style="font-family:Arial;font-size:12px;padding:6px;">', CAST(PERIODO AS STRING), '</th>'),
        '' ORDER BY PERIODO ASC
      ),
      '</tr>'
    ) AS html
    FROM periodos
  ),
  filas AS (
    SELECT
      t.SVA_SMS, t.rn,
      STRING_AGG(
        CONCAT(
          '<td style="font-family:Arial;font-size:11px;text-align:right;padding:5px;">',
          IFNULL(
            CONCAT('$ ', REVERSE(ARRAY_TO_STRING(ARRAY(
              SELECT REGEXP_EXTRACT(x, r'\d{1,3}')
              FROM UNNEST(REGEXP_EXTRACT_ALL(REVERSE(CAST(CAST(IFNULL(s.ARPU, 0) AS INT64) AS STRING)), r'\d{1,3}')) AS x
            ), '.'))),
            '-'
          ),
          '</td>'
        ),
        '' ORDER BY p.PERIODO ASC
      ) AS celdas
    FROM tipos t
    CROSS JOIN periodos p
    LEFT JOIN PARQUE_ARPU_SMSP s ON s.SVA_SMS = t.SVA_SMS AND s.PERIODO = p.PERIODO
    GROUP BY t.SVA_SMS, t.rn
  ),
  totales AS (
    SELECT
      PERIODO,
      ROUND(SUM(Q_TRANSACCIONES * MONTO_NETO) / NULLIF(SUM(Q_TRANSACCIONES), 0), 0) AS arpu_periodo
    FROM `TU_PROJECT_ID.TU_DATASET_ID.NOMBRE_TABLA_TRX`
    WHERE PERIODO >= CAST(FORMAT_DATE('%Y%m', DATE_SUB(CURRENT_DATE(), INTERVAL 7 MONTH)) AS INT)
      AND TIPO = 'SMSP'
    GROUP BY PERIODO
  ),
  totales_html AS (
    SELECT CONCAT(
      '<tr style="background:#4d008c;color:#ffffff;font-weight:bold;">',
      '<td style="font-family:Arial;font-size:12px;padding:6px;" colspan="2">Ticket promedio</td>',
      STRING_AGG(
        CONCAT(
          '<td style="font-family:Arial;font-size:11px;text-align:right;padding:5px;">',
          CONCAT('$ ', REVERSE(ARRAY_TO_STRING(ARRAY(
            SELECT REGEXP_EXTRACT(x, r'\d{1,3}')
            FROM UNNEST(REGEXP_EXTRACT_ALL(REVERSE(CAST(CAST(arpu_periodo AS INT64) AS STRING)), r'\d{1,3}')) AS x
          ), '.'))),
          '</td>'
        ),
        '' ORDER BY PERIODO ASC
      ),
      '</tr>'
    ) AS html
    FROM totales
  )
  SELECT CONCAT(
    '<p style="font-family:Arial;font-size:13px;font-weight:bold;color:#4d008c;margin:20px 0 8px;">',
    'Top 10 Ticket promedio SMSP</p>',
    '<table width="100%" cellpadding="5" cellspacing="0" ',
    'style="font-family:Arial;font-size:12px;border-collapse:collapse;border:1px solid #cccccc;">',
    (SELECT html FROM header),
    (
      SELECT STRING_AGG(
        CONCAT(
          '<tr style="background:', IF(MOD(rn,2)=0,'#f3f3f3','#ffffff'), ';">',
          '<td style="font-family:Arial;font-size:11px;padding:5px;text-align:center;',
          'color:#7c3aed;font-weight:bold;">', CAST(rn AS STRING), '</td>',
          '<td style="font-family:Arial;font-size:11px;padding:5px;text-align:left;',
          'color:#4d008c;font-weight:bold;">', SVA_SMS, '</td>',
          celdas,
          '</tr>'
        ),
        '' ORDER BY rn
      )
      FROM filas
    ),
    (SELECT html FROM totales_html),
    '</table>'
  )
);

-- ============================================================
-- BOTÓN LOOKER
-- ============================================================
SET boton = CONCAT(
  '<div style="text-align:center;margin:16px 0;">',
  '<a href="TU_URL_LOOKER" ',  -- Reemplaza con la URL de tu reporte en Looker
  'style="font-family:Arial;font-size:13px;text-decoration:none;color:#ffffff;',
  'background:#3b2b58;padding:10px 24px;border-radius:4px;display:inline-block;">',
  'Ver Reporte en Looker</a></div>'
);

-- ============================================================
-- ENSAMBLE BODY
-- ============================================================
SET titulo = 'Reporte Parque Suscriptores';  -- Reemplaza con el título de tu reporte

SET Body_HTML = CONCAT(
  '<p style="font-family:Arial;font-size:14px;">Hola,</p>',
  '<p style="font-family:Arial;font-size:14px;">',
  'Junto con saludar, se adjunta el reporte de <strong>Parque Suscriptores</strong>, ',
  'con la evolución de líneas suscritas por tipo (SMS / SVA) de los últimos 8 meses.',
  '</p>',

  grafico_html,
  tabla_sva_html,
  tabla_smsp_html,
  tabla_arpu_sva_html,
  tabla_arpu_smsp_html,

  '<p style="font-family:Arial;font-size:13px;margin-top:16px;">Saludos cordiales,</p>',
  '<p style="font-family:Arial;font-size:13px;"><strong>Equipo BA</strong></p>',
  '<p style="font-family:Arial;font-size:13px;">TU_EMAIL_EQUIPO</p>',  -- Reemplaza con tu correo

  '<table width="100%" cellpadding="0" cellspacing="0" style="margin-top:20px;border-top:4px solid #7c3aed;">',
  '<tr><td style="padding:12px;font-family:Arial;">',
  '<p style="color:#4d008c;font-size:13px;font-weight:bold;margin:8px 0;">Notas</p>',
  '<ul style="font-size:12px;color:#2d1540;padding-left:20px;">',
  '<li style="margin-bottom:6px;">Fuente: NOMBRE_TABLA_PARQUE</li>',  -- Reemplaza con el nombre de tu tabla
  '<li style="margin-bottom:6px;">Este mail es generado automáticamente.</li>',
  '</ul>',
  '</td></tr></table>'
);

-- ============================================================
-- PLANTILLA + ASUNTO
-- ============================================================
SET cuerpo_correo = (
  SELECT `TU_PROJECT_ID.TU_DATASET_ID.NOMBRE_FX_PLANTILLA`(  -- Reemplaza con tu función de plantilla
    titulo,
    CAST(FORMAT_DATE('%d-%m-%Y', CURRENT_DATE()) AS STRING),
    Body_HTML,
    boton
  )
);

SET asunto = CONCAT(
  '[BA] Reporte Parque Suscriptores [',
  FORMAT_DATE('%Y%m%d', CURRENT_DATE()),
  ']'
);

END
