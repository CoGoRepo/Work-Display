// Set up Google Sheets API client
const { Client, GatewayIntentBits, EmbedBuilder } = require('discord.js');
const { google } = require('googleapis');
const credentials = require('./googlesheets.json');

const client = new Client({
    intents: [
        GatewayIntentBits.Guilds,
        GatewayIntentBits.GuildMessages,
        GatewayIntentBits.MessageContent,
        GatewayIntentBits.GuildMessageReactions // Ensure this intent is enabled
    ]
});

// Set up Google Sheets API client
const auth = new google.auth.GoogleAuth({
    credentials: credentials,
    scopes: ['https://www.googleapis.com/auth/spreadsheets'],
});
const sheets = google.sheets({version: 'v4', auth});

const spreadsheetId = '13S4pd7OmRUh2xe9LylvpvWf7llsQxskkUY1Z5bwTLmo';
const sheetName = 'Sheet1';  // Adjust this to your actual sheet name if different
const adminRoleName = 'admin'; // Adjust this to match the role name of your admins

client.on('ready', () => {
    console.log(`Logged in as ${client.user.tag}!`);
});

client.on('messageCreate', async message => {
    if (!message.content.startsWith('!pb') || message.author.bot) return;

    const args = message.content.slice(4).trim().split(/\s+/).filter(arg => !arg.match(/https?:\/\/\S+/));
    const boss = args[0].toLowerCase();
    const time = args[1];
    const teamMembers = args.slice(2).map(user => user.replace(/<@!?(\d+)>/, '$1'));

    if (!/^\d{2}:\d{2}$/.test(time)) {
        return message.reply("Invalid time format. Please enter the time in MM:SS format, e.g., 00:53.");
    }

    try {
        const range = `${sheetName}!A2:F`;
        const response = await sheets.spreadsheets.values.get({ spreadsheetId, range });
        const rows = response.data.values || [];
        const bossRows = rows.filter(row => row[0].toLowerCase() === boss);

        if (bossRows.length === 0) {
            return message.reply(`No data found for boss: ${boss}. Please check the boss name and try again.`);
        }

        const requiredSize = bossRows[0][4] ? parseInt(bossRows[0][4]) : null;
        const names = [message.member.nickname || message.author.username, ...teamMembers.map(id => message.guild.members.cache.get(id)?.nickname || message.guild.members.cache.get(id)?.user.username)];
        names.sort();
        const teamName = names.join(', ');
        
        // Skip the size check if requiredSize is null
        if (requiredSize !== null && names.length !== requiredSize) {
            return message.reply(`Incorrect team size. Required: ${requiredSize}, but found: ${names.length}.`);
        }

        let isFaster = true;
        let duplicateEntry = false;
        let slowestTime = null;
        let slowestRowNum = null;

        bossRows.forEach((row) => {
            const rowNum = parseInt(row[5]);
            if (row[1] && time >= row[1] && (isFaster || !slowestTime || row[1] > slowestTime)) {
                isFaster = false;
                slowestTime = row[1];
                slowestRowNum = rowNum;
            }
            if (row[2] === teamName && time >= row[1]) {
                duplicateEntry = true;
            }
        });

        if (duplicateEntry) {
            return message.reply(`A faster time or an existing time by the same team already exists on the leaderboard.`);
        }

        if (isFaster || bossRows.length < 3) {
            const embed = new EmbedBuilder()
                .setColor(0x0099FF)
                .setTitle('New Time Submission Approval Needed')
                .setDescription(`**Boss:** ${boss}\n**Time:** ${time}\n**Team:** ${teamName}\n\nReact with ✅ to approve or ❌ to deny.`)
                .setFooter({ text: 'Approval request' });
    
            const approvalMessage = await message.channel.send({ embeds: [embed] });
            approvalMessage.react('✅');
            approvalMessage.react('❌');

            const filter = (reaction, user) => ['✅', '❌'].includes(reaction.emoji.name) && !user.bot && message.guild.members.cache.get(user.id).roles.cache.some(role => role.name === adminRoleName);
            const collector = approvalMessage.createReactionCollector({ filter, max: 1, time: 60000 });

            collector.on('collect', async (reaction) => {
                if (reaction.emoji.name === '✅') {
                    const currentDate = new Date().toLocaleDateString('en-US', { month: '2-digit', day: '2-digit', year: 'numeric' }).replace(/\//g, '-');
                    if (isFaster && slowestRowNum && bossRows.length >= 3) {
                        const updateRange = `${sheetName}!B${slowestRowNum}:E${slowestRowNum}`;
                        const values = [[time, teamName, currentDate]];
                        await sheets.spreadsheets.values.update({
                            spreadsheetId,
                            range: updateRange,
                            valueInputOption: 'USER_ENTERED',
                            requestBody: { values },
                        });
                    } else {
                        const nextRowNum = bossRows.reduce((max, row) => Math.max(max, parseInt(row[5])), 0) + 1;
                        const updateRange = `${sheetName}!A${nextRowNum}:E${nextRowNum}`;
                        const values = [[boss, time, teamName, currentDate]];
                        await sheets.spreadsheets.values.update({
                            spreadsheetId,
                            range: updateRange,
                            valueInputOption: 'USER_ENTERED',
                            requestBody: { values },
                        });
                    }
                    message.reply(`The new time for ${boss} has been approved and recorded: ${time} by ${teamName}.`);
                    approvalMessage.delete();
                } else {
                    message.reply('The new time submission has been denied.');
                    approvalMessage.delete();
                }
            });
        } else {
            return message.reply('Time not fast enough or leaderboard already full.');
        }
    } catch (error) {
        console.error('Failed to retrieve data:', error);
        return message.reply('Failed to retrieve data from Google Sheets.');
    }
});

client.login('removed-for-security');
