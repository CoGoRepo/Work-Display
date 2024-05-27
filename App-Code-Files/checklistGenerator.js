const { pool } = require('./database');
const fs = require('fs').promises;
const path = require('path');

// Update the path to point to the MASTER-CHECKLIST.CKLB file in your project directory
const masterChecklistPath = path.join(__dirname, 'MASTER-CHECKLIST.CKLB');

async function readMasterChecklist() {
    const data = await fs.readFile(masterChecklistPath, 'utf8');
    return JSON.parse(data);
}

async function generateChecklistForAsset(assetId, name, products) {
    if (!products || products.length === 0) {
        throw new Error('Products array is null or empty');
    }
    const masterChecklist = await readMasterChecklist();
    // Filter logic based on the products...
    const filteredChecklist = {
        ...masterChecklist,
        // Customize the filtering logic as needed
        stigs: masterChecklist.stigs.filter(stig => products.includes(stig.display_name)),
        target_data: { hostname: name } // Adding asset name to target_data
    };
    // Here, you would either return this checklist to be sent to the user or store it temporarily
    return filteredChecklist;
}

async function fetchAssetVulnerabilities(assetId) {
    const query = `
        SELECT v.rule_id, av.status, av.comment 
        FROM assetvulnerabilities av
        JOIN vulnerabilities v ON av.vulnerability_id = v.vulnerability_id
        WHERE av.asset_id = $1;
    `;
    const { rows } = await pool.query(query, [assetId]);
    return rows;
}

async function updateChecklistWithVulnerabilities(assetId, checklist) {
    const vulnerabilities = await fetchAssetVulnerabilities(assetId);

    checklist.stigs.forEach(stig => {
        stig.rules.forEach(rule => {
            // Find the vulnerability by rule_id
            const vulnerability = vulnerabilities.find(v => v.rule_id === rule.rule_id);
            if (vulnerability) {
                // Update the checklist's rule with status and comments from the database
                rule.status = vulnerability.status;
                rule.comments = vulnerability.comment;
            }
        });
    });

    return checklist;
}

module.exports = { generateChecklistForAsset, updateChecklistWithVulnerabilities };
