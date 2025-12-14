//+------------------------------------------------------------------+
//|                                                 DisplayPanel.mqh |
//|                       Class for an on-chart information panel    |
//|                                  Copyright 2023, Your Name Here  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2023, Your Name Here"
#property link      "https://www.mql5.com"

//+------------------------------------------------------------------+
//| CDisplayPanel Class                                              |
//+------------------------------------------------------------------+
class CDisplayPanel
  {
private:
   string            m_chart_name;
   int               m_x_pos;
   int               m_y_pos;
   color             m_text_color;

   //--- Create a text object
   void              CreateText(string name, string text, int y_offset)
     {
      ObjectCreate(0, m_chart_name + name, OBJ_LABEL, 0, 0, 0);
      ObjectSetString(0, m_chart_name + name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, m_chart_name + name, OBJPROP_XDISTANCE, m_x_pos);
      ObjectSetInteger(0, m_chart_name + name, OBJPROP_YDISTANCE, m_y_pos + y_offset);
      ObjectSetInteger(0, m_chart_name + name, OBJPROP_COLOR, m_text_color);
      ObjectSetInteger(0, m_chart_name + name, OBJPROP_FONTSIZE, 10);
      ObjectSetString(0, m_chart_name + name, OBJPROP_FONT, "Arial");
     }

public:
   //--- Constructor
                     CDisplayPanel(string chart_name, int x, int y, color text_col)
     {
      m_chart_name = chart_name;
      m_x_pos = x;
      m_y_pos = y;
      m_text_color = text_col;
     }

   //--- Destructor
                    ~CDisplayPanel()
     {
      ObjectDelete(0, m_chart_name + "_Title");
      ObjectDelete(0, m_chart_name + "_Profit");
      ObjectDelete(0, m_chart_name + "_Trades");
      ObjectDelete(0, m_chart_name + "_LotSize");
      ObjectDelete(0, m_chart_name + "_Status");
     }

   //--- Initialize the panel
   void              Init(string title)
     {
      CreateText("_Title", title, 0);
      CreateText("_Profit", "Floating P/L: 0.00", 20);
      CreateText("_Trades", "Trades (B/S): 0 / 0", 40);
      CreateText("_LotSize", "Next Lot Size: 0.00", 60);
      CreateText("_Status", "Status: Initializing...", 80);
     }

   //--- Update the panel's information
   void              Update(double pnl, int buy_trades, int sell_trades, double lot_size, string status)
     {
      ObjectSetString(0, m_chart_name + "_Profit", OBJPROP_TEXT, "Floating P/L: " + DoubleToString(pnl, 2));
      ObjectSetString(0, m_chart_name + "_Trades", OBJPROP_TEXT, "Trades (B/S): " + IntegerToString(buy_trades) + " / " + IntegerToString(sell_trades));
      ObjectSetString(0, m_chart_name + "_LotSize", OBJPROP_TEXT, "Next Lot Size: " + DoubleToString(lot_size, 2));
      ObjectSetString(0, m_chart_name + "_Status", OBJPROP_TEXT, "Status: " + status);
     }
  };
//+------------------------------------------------------------------+
