         <tr>
           <td colspan="2"><b><u>Round Shares</u></b> <span id='tt'><img src='{$PATH}/images/questionmark.png' height='15px' width='15px' title='Submitted shares since last found block (ie. round shares)'></span></td>
         </tr>
         <tr>
           <td><b>Est. Shares</b></td>
           <td id="b-target" class="right">{$ESTIMATES_MM5.shares|number_format} (done: {$ESTIMATES_MM5.percent}%)</td>
         </tr>
         <tr>
           <td><b>Pool Valid</b></td>
           <td id="b-pvalid" class="right">{$GLOBAL.roundshares_mm5.valid|number_format}</td>
         </tr>
         <tr>
           <td><b>Your Valid<b></td>
           <td id="b-yvalid" class="right">{$GLOBAL.userdata.shares_mm5.valid|number_format}</td>
         </tr>
         <tr>
           <td><b>Pool Invalid</b></td>
           <td id="b-pivalid" class="right">{$GLOBAL.roundshares_mm5.invalid|number_format} {if $GLOBAL.roundshares_mm5.valid > 0}({($GLOBAL.roundshares_mm5.invalid / ($GLOBAL.roundshares_mm5.valid + $GLOBAL.roundshares_mm5.invalid) * 100)|number_format:"2"}%){else}(0.00%){/if}</td></td>
         </tr>
         <tr>
           <td><b>Your Invalid</b></td>
           <td id="b-yivalid" class="right">{$GLOBAL.userdata.shares_mm5.invalid|number_format} {if $GLOBAL.userdata.shares_mm5.valid > 0}({($GLOBAL.userdata.shares_mm5.invalid / ($GLOBAL.userdata.shares_mm5.valid + $GLOBAL.userdata.shares_mm5.invalid) * 100)|number_format:"2"}%){else}(0.00%){/if}</td>
         </tr>
