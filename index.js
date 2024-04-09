const Discord = require('discord.js');
const axios = require('axios');
const cheerio = require('cheerio');

const client = new Discord.Client();

// Configuration
const WEBSITES = [
    {
        name: 'Site 1',
        url: 'https://example1.com',
        selector: 'selector_for_latest_update_element_1'
    },
    {
        name: 'Site 2',
        url: 'https://example2.com',
        selector: 'selector_for_latest_update_element_2'
    },
    // Add more sites as needed
];
const INTERVAL = 60000; // Check every minute (adjust as needed)
const CHANNEL_ID = 'YOUR_CHANNEL_ID'; // Replace with the ID of the channel where you want to send updates

let latestUpdates = {};

// Function to fetch the website content
async function fetchWebsite(url) {
    try {
        const response = await axios.get(url);
        return response.data;
    } catch (error) {
        console.error('Error fetching website:', error);
        return null;
    }
}

// Function to parse website content and check for updates
function checkForUpdates(html, selector) {
    const $ = cheerio.load(html);
    const latestUpdateElement = $(selector);

    const updateText = latestUpdateElement.text().trim();

    if (updateText !== latestUpdates[selector]) {
        latestUpdates[selector] = updateText;
        return updateText;
    }

    return null;
}

// Function to send update message to Discord
function sendUpdateMessage(siteName, updateText) {
    const channel = client.channels.cache.get(CHANNEL_ID);
    if (channel) {
        channel.send(`New update on ${siteName}: ${updateText}`);
    } else {
        console.error('Invalid channel ID');
    }
}

// Main function to run the bot
async function main() {
    for (const site of WEBSITES) {
        const html = await fetchWebsite(site.url);
        if (!html) continue;

        const updateText = checkForUpdates(html, site.selector);
        if (updateText) {
            sendUpdateMessage(site.name, updateText);
        }
    }
}

// Event listener for when the bot is ready
client.on('ready', () => {
    console.log(`Logged in as ${client.user.tag}!`);
    setInterval(main, INTERVAL);
});

// Log in to Discord with your bot token
client.login('YOUR_BOT_TOKEN'); // Replace with your bot token
