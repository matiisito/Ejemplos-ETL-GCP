-- ============================================================
-- CONFIGURACIÓN — Reemplaza estos valores antes de ejecutar
-- ============================================================
--   TU_PROJECT_ID           → ID de tu proyecto GCP principal     Ej: 'mi-proyecto-gcp'
--   TU_DATASET_ID           → Dataset principal                    Ej: 'mi_dataset'
--   TU_PROJECT_CALENDARIO   → Proyecto donde está la tabla de días Ej: 'mi-proyecto-calendario'
--   TU_DATASET_CALENDARIO   → Dataset del calendario               Ej: 'DWH'
--   NOMBRE_TABLA_PARQUE     → Tabla de parque suscriptores         Ej: 'Parque_Suscriptores'
--   NOMBRE_TABLA_CALENDARIO → Tabla de tipo de día                 Ej: 'LK_TPO_DIA'
--   NOMBRE_TABLA_CORREOS    → Tabla de envío de correos            Ej: 'Envio_Correos'
--   NOMBRE_FX_CORREO        → Procedimiento que arma el correo     Ej: 'Fx_Correo_Parque'
--   EMAIL_PARA              → Destinatario principal               Ej: 'destinatario@tudominio.com'
--   EMAIL_CC                → Destinatarios en copia (separados por coma)
-- ============================================================

BEGIN
  DECLARE num_rows INT64;
  DECLARE asunto STRING DEFAULT NULL;
  DECLARE cuerpo_correo STRING DEFAULT NULL;

  -- 1. Cuenta los registros del período
  SET num_rows = (
    SELECT COUNT(*)
    FROM `TU_PROJECT_ID.TU_DATASET_ID.NOMBRE_TABLA_PARQUE`
    WHERE PERIODO >= CAST(FORMAT_DATE('%Y%m', DATE_SUB(CURRENT_DATE(), INTERVAL 7 MONTH)) AS INT)
  );

  -- 2. Solo ejecuta si hay datos Y es lunes o viernes
  --    Ajusta los días según tu necesidad (ej: 'MONDAY', 'FRIDAY' si tu calendario está en inglés)
  IF num_rows > 0
    AND (
      SELECT DAYNAMELONG
      FROM `TU_PROJECT_CALENDARIO.TU_DATASET_CALENDARIO.NOMBRE_TABLA_CALENDARIO`
      WHERE DIA_FECHA = CURRENT_DATE()
    ) IN ('LUNES', 'VIERNES')
  THEN

    -- 3. Llama al procedimiento que genera el asunto y cuerpo del correo
    CALL `TU_PROJECT_ID.TU_DATASET_ID.NOMBRE_FX_CORREO`(asunto, cuerpo_correo);

    -- 4. Elimina envío previo con el mismo asunto (evita duplicados)
    DELETE FROM `TU_PROJECT_ID.TU_DATASET_ID.NOMBRE_TABLA_CORREOS`
    WHERE SUBJECT = ASUNTO;

    -- 5. Inserta el nuevo registro para envío (PROCESADO='N' lo tomará el job de envío)
    INSERT INTO `TU_PROJECT_ID.TU_DATASET_ID.NOMBRE_TABLA_CORREOS`
      (FECHA, PARA, CC, SUBJECT, BODY, PROCESADO)
    SELECT
      CURRENT_DATE('-3')    AS FECHA,
      'EMAIL_PARA'          AS PARA,       -- Reemplaza con el correo destinatario
      'EMAIL_CC'            AS CC,         -- Reemplaza con los correos en copia
      ASUNTO                AS SUBJECT,
      CUERPO_CORREO         AS BODY,
      'N'                   AS PROCESADO;

  END IF;

END
