// @ts-nocheck

// ─────────────────────────────────────────────
// CONFIGURACIÓN — Reemplaza estos valores
// ─────────────────────────────────────────────
const PROJECT_ID  = 'TU_PROJECT_ID';               // Ej: 'mi-proyecto-gcp-1234'
const DATASET_ID  = 'TU_DATASET_ID';               // Ej: 'mi_dataset'
const TABLE_ID    = 'NOMBRE_TABLA_ENVIO_CORREOS';  // Ej: 'Envio_Correos'
const FROM_EMAIL  = 'TU_CORREO_REMITENTE';         // Ej: 'notificaciones@tudominio.com'
// ─────────────────────────────────────────────

function runQuery() {
  const fullTable = `${PROJECT_ID}.${DATASET_ID}.${TABLE_ID}`;

  // 1. Consulta los registros pendientes (procesado = 'N')
  const request = {
    query: `SELECT * FROM \`${fullTable}\` WHERE procesado = "N"`,
    useLegacySql: false
  };

  let queryResults = BigQuery.Jobs.query(request, PROJECT_ID);
  const jobId = queryResults.jobReference.jobId;

  // 2. Espera a que el job termine
  let sleepTimeMs = 500;
  while (!queryResults.jobComplete) {
    Utilities.sleep(sleepTimeMs);
    sleepTimeMs *= 2;
    queryResults = BigQuery.Jobs.getQueryResults(PROJECT_ID, jobId);
  }

  // 3. Obtiene todas las filas (paginado)
  let rows = queryResults.rows;
  while (queryResults.pageToken) {
    queryResults = BigQuery.Jobs.getQueryResults(PROJECT_ID, jobId, {
      pageToken: queryResults.pageToken
    });
    rows = rows.concat(queryResults.rows);
  }

  if (!rows) {
    Logger.log('No hay filas pendientes de envío.');
    return;
  }

  // 4. Convierte filas a array
  const data = new Array(rows.length);
  for (let i = 0; i < rows.length; i++) {
    const cols = rows[i].f;
    data[i] = new Array(cols.length);
    for (let j = 0; j < cols.length; j++) {
      data[i][j] = cols[j].v;
    }
  }

  // 5. Envía cada correo y actualiza el estado a 'S'
  // Estructura esperada de columnas:
  //   [0] ID  |  [1] TO  |  [2] CC  |  [3] SUBJECT  |  [4] HTML_BODY
  for (let i = 0; i < data.length; i++) {
    MailApp.sendEmail({
      to:       data[i][1],
      cc:       data[i][2],
      subject:  data[i][3],
      htmlBody: data[i][4],
      from:     FROM_EMAIL
    });

    Logger.log('Correo enviado: ' + data[i][3]);

    // Marca el registro como procesado
    const updateRequest = {
      query: `UPDATE \`${fullTable}\` SET PROCESADO = "S" WHERE procesado = "N" AND SUBJECT = "${data[i][3]}";`,
      useLegacySql: false
    };
    BigQuery.Jobs.query(updateRequest, PROJECT_ID);
  }
}
