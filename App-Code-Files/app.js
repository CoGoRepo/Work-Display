const { generateChecklistForAsset, updateChecklistWithVulnerabilities } = require('./checklistGenerator');
const { pool } = require('./database');

// Initialization and Module Imports
const express = require('express');
const cors = require('cors');
const path = require('path');
const app = express();
const port = 8000;


// Middleware and CORS Setup
app.use(cors());
app.use(express.static(path.join(__dirname, 'public')));
app.use(express.json())


// Checklist creation Endpoint
app.post('/api/generate-checklist', async (req, res) => {
  try {
      const { assetId, name, products } = req.body;
      let checklist = await generateChecklistForAsset(assetId, name, products);
      checklist = await updateChecklistWithVulnerabilities(assetId, checklist);
      // Depending on your implementation, either send the checklist as a file or JSON
      res.json(checklist);
  } catch (error) {
      console.error('Error generating checklist:', error);
      res.status(500).send('Server error');
  }
});


// Endoint to populate Assets GRID
app.get('/api/assets', async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT asset_id, name, role, operatingsystem, build, ipaddress, additionalinfo, ssp
      FROM assets;
    `);
    const formattedData = result.rows.map(asset => ({
      ...asset,
      ipaddress: asset.ipaddress.toString(),
      additionalinfo: asset.additionalinfo && asset.additionalinfo.products ? 
          asset.additionalinfo.products.join('\n') : '' // Join products with a comma
    }));
    res.json(formattedData);
  } catch (error) {
    console.error('Error fetching assets:', error);
    res.status(500).send('Server error');
  }
});


//Start Endpoint to populate vulnerabilities GRID
app.get('/api/vulnerabilities', async (req, res) => {
  try {
    const query = `
    SELECT 
    a.ssp, 
    a.name,
    v.group_id, 
    v.rule_version,
    v.rule_id,
    v.severity, 
    av.aor,
    v.rule_title,
    av.status, 
    av.scan_date, 
    av.resolveddate, 
    av.comment, 
    av.changedby, 
    v.product, 
    av.vulnerability_id,
    av.asset_id
FROM assetvulnerabilities av
JOIN assets a ON av.asset_id = a.asset_id
JOIN vulnerabilities v ON av.vulnerability_id = v.vulnerability_id;
  `;
    const { rows } = await pool.query(query);
    // Function to format date to yyyy-MM-dd
    const formatDate = (dateString) => {
      if (!dateString) return null; // Handle null dates
      const date = new Date(dateString);
      return date.toISOString().split('T')[0]; // Splits the ISO string and takes the date part
    };
    // Apply date formatting to each row
    const formattedRows = rows.map(row => ({
      ...row,
      scan_date: formatDate(row.scan_date),
      resolveddate: formatDate(row.resolveddate)
    }));
    res.json(formattedRows);
  } catch (error) {
    console.error('Error fetching vulnerabilities data:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});


// Endpoint to update changes to vulnerabilities grid
app.put('/api/vulnerabilities/update', async (req, res) => {
  const updates = req.body; // An array of updates
  const updatedRows = []; // To store the updated row data

  try {
    for (const update of updates) {
      let query = `UPDATE assetvulnerabilities SET `;
      let params = [];
      let paramCounter = 1;
      if (update.field === 'comment') {
        query += `comment = COALESCE(comment, '') || '\n' || $${paramCounter++}`;
        params.push(update.value);
      } else {
          // For fields other than 'comment', directly set the new value
          query += `${update.field} = $${paramCounter++}`;
          params.push(update.value);
          
          // Additional logic for 'status' field to set/clear 'resolveddate'
          if (update.field === 'status') {
              if (update.value === 'not_a_finding' || update.value === 'not_applicable') {
                  query += `, resolveddate = $${paramCounter++}`;
                  params.push(new Date().toISOString().split('T')[0]);
              } else if (update.value === 'open' || update.value === 'not_reviewed') {
                  query += `, resolveddate = $${paramCounter++}`;
                  params.push(null);
              }
          }
      }
      query += ` WHERE asset_id = $${paramCounter++} AND vulnerability_id = $${paramCounter}`;
      params.push(update.asset_id, update.vulnerability_id);
      // Execute the update query
      await pool.query(query, params);
      // Fetch and add the updated row data to the response, if needed
      const fetchQuery = `SELECT * FROM assetvulnerabilities WHERE asset_id = $1 AND vulnerability_id = $2`;
      const { rows } = await pool.query(fetchQuery, [update.asset_id, update.vulnerability_id]);
      if (rows.length > 0) {
          updatedRows.push(rows[0]);
      }
  }      // Respond with the updated rows
      res.json({ message: 'Updates successful', updatedRows: updatedRows });
  } catch (error) {
      console.error('Error updating asset vulnerabilities:', error);
      res.status(500).send({ message: 'Error processing updates' });
  }
});

// Endpoint for vuln-grid modal
app.get('/api/vulnerabilityDetails/:vulnerabilityId', async (req, res) => {
  const { vulnerabilityId } = req.params;

  try {
    const queryText = 'SELECT check_content, fix_text FROM vulnerabilities WHERE vulnerability_id = $1';
    const { rows } = await pool.query(queryText, [vulnerabilityId]);
    if (rows.length > 0) {
      res.json(rows[0]);
    } else {
      res.status(404).send({ message: 'Vulnerability details not found.' });
    }
  } catch (error) {
    console.error('Error fetching vulnerability details:', error);
    res.status(500).send({ message: 'Internal server error' });
  }
});


// Endpoint for openVulnerabilities Card
app.get('/api/stats/openVulnerabilities', async (req, res) => {
  const ssp = req.query.ssp;
  // Check if ssp is "ALL" or not provided
  if (ssp === 'ALL' || !ssp) {
    query = "SELECT COUNT(*) AS count FROM assetvulnerabilities WHERE status IN ('open', 'not_reviewed')";
  } else {
    query = `
      SELECT COUNT(*) AS count
      FROM assetvulnerabilities av
      JOIN assets a ON av.asset_id = a.asset_id
      WHERE a.ssp = $1 AND av.status IN ('open', 'not_reviewed');
    `;
  }
  try {
    const params = ssp && ssp !== 'ALL' ? [ssp] : [];
    const { rows } = await pool.query(query, params);
    res.json({ count: rows[0].count });
  } catch (error) {
    console.error('Error fetching non-resolved vulnerabilities count:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint for totalAssets Card
app.get('/api/stats/totalAssets', async (req, res) => {
  const ssp = req.query.ssp;
  let query;
  if (ssp === 'ALL' || !ssp) {
    // If "ALL" is selected, count all assets without filtering by SSP
    query = "SELECT COUNT(*) AS count FROM assets";
  } else {
    // Otherwise, filter by the selected SSP
    query = "SELECT COUNT(*) AS count FROM assets WHERE ssp = $1";
  }
  try {
    const params = ssp && ssp !== 'ALL' ? [ssp] : [];
    const { rows } = await pool.query(query, params);
    res.json({ count: rows[0].count });
  } catch (error) {
    console.error('Error fetching non-resolved vulnerabilities count:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Endpoint for ResolvedThisMonth Card
app.get('/api/stats/resolvedThisMonth', async (req, res) => {
  const currentDate = new Date();
  const currentMonth = currentDate.getMonth() + 1; // JavaScript months are 0-indexed
  const currentYear = currentDate.getFullYear();
  const ssp = req.query.ssp;

  let query = `
    SELECT COUNT(av.*) AS count 
    FROM assetvulnerabilities av
    JOIN assets a ON av.asset_id = a.asset_id
    WHERE EXTRACT(MONTH FROM av.resolveddate) = $1 
    AND EXTRACT(YEAR FROM av.resolveddate) = $2
  `;
  const params = [currentMonth, currentYear];
  // Filter by SSP if provided and not "ALL"
  if (ssp && ssp !== 'ALL') {
    query += ` AND a.ssp = $3`;
    params.push(ssp);
  }
  try {
    const { rows } = await pool.query(query, params);
    res.json({ count: rows[0].count });
  } catch (error) {
    console.error('Error fetching resolved vulnerabilities count for this month with SSP filter:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Create Graph1
app.get('/api/vulnerabilityCountsByProduct', async (req, res) => {
  const { ssp } = req.query;
  let baseQuery = `
    SELECT v.product, COUNT(av.vulnerability_id) AS vulnerability_count
    FROM assetvulnerabilities av
    JOIN assets a ON av.asset_id = a.asset_id
    JOIN vulnerabilities v ON av.vulnerability_id = v.vulnerability_id
    WHERE av.status IN ('open', 'not_reviewed')
  `;
  if (ssp && ssp !== 'ALL') {
    baseQuery += ` AND a.ssp = $1`;
  }
  baseQuery += ' GROUP BY v.product';
  try {
    const params = ssp !== 'ALL' ? [ssp] : [];
    const { rows } = await pool.query(baseQuery, params);
    // Transform the data to the expected format
    const transformedData = rows.map(row => ({
      product: row.product,
      openVulnerabilities: parseInt(row.vulnerability_count, 10) // Explicitly parse as integer
    }));
    res.json(transformedData);
  } catch (error) {
    console.error('Error fetching data:', error);
    res.status(500).send('Server error');
  }
});

// Create Graph2
app.get('/api/vulnerability-snapshot', async (req, res) => {
  const { ssp } = req.query; // This will be used to filter the data by SSP

  try {
      const query = 'SELECT snapshot_date, ssp, open_count, total_vulnerabilities_count FROM vulnerability_snapshot WHERE ssp = $1 AND snapshot_date > CURRENT_DATE - INTERVAL \'30 days\' ORDER BY snapshot_date';
      const values = [ssp];
      
      const results = await pool.query(query, values);
      
      // Transform the data for frontend consumption, ensuring counts are integers
      const transformedData = results.rows.map(row => ({
          date: row.snapshot_date,  // Keeping the date format consistent
          ssp: row.ssp,             // Including the SSP in the transformed data
          openVulnerabilities: parseInt(row.open_count, 10), // Ensuring count is an integer
          totalVulnerabilities: parseInt(row.total_vulnerabilities_count, 10) // Ensuring total count is an integer
      }));
      
      res.json(transformedData);
  } catch (error) {
      console.error('Error fetching vulnerability snapshot:', error);
      res.status(500).json({ error: 'Server error' });
  }
});



//Listener. Keep at bottom of page.
app.listen(port, () => {
  console.log(`Backend service running at http://localhost:${port}`);
});