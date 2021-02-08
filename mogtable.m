classdef mogtable
    properties(SetAccess = protected)
        parent
        channel
    end
    
    properties
        t
        freq
        pow
        phase
    end
    
    properties(Constant)
        FREQ_BITS = 32;
        CLK = 1e3;  %In MHz, so 1 GHz
        MODES = {'NSB','NSA','TSB'};
    end
    
    methods
        function self = mogtable(parent,channel)
            if ~isa(parent,'mogdevice')
                error('Parent must be a ''mogdevice'' object!');
            end
            self.parent = parent;
            self.channel = channel;
        end
        
        function self = check(self)
            %Check times
%             if any(diff(self.t) < 1e-6)
%                 error('Time steps must be at least 1 us');
%             end
            %Check frequencies
            if any(self.freq > 400) || any(self.freq < 10)
                error('Frequencies must be between [10,400] MHz');
            end
            %Check powers
            if any(self.pow > 35.1)
                error('Powers must be below 35.1 dBm');
            end
            %Wrap phase
            self.phase = mod(self.phase,360);
        end
        
        function self = upload(self)
            self.check;
            self.parent.cmd('mode,%d,%s',self.channel,'TSB');
            self.parent.cmd('table,clear,%d',self.channel);
            dt = diff(self.t);
            dt = dt(:);
            dt(end+1) = 10e-6; %#ok<*NASGU>
            N = numel(dt);
            if N > 8191
                error('Maximum number of table entries is 8191');
            end
            for nn = 1:N
                f = self.freq(min(nn,numel(self.freq)));
                p = self.pow(min(nn,numel(self.pow)));
                ph = self.phase(min(nn,numel(self.phase)));
                self.parent.cmd('table,append,%d,%.6f,%.4f,%.6f,%d',...
                    self.channel,f,p,ph,ceil(dt(nn)*1e6));
            end
            self.parent.cmd('table,arm,%d',self.channel);
            self.parent.cmd('table,rearm,%d,on',self.channel);
        end
        
    end
    
    methods(Static)
        function rf = opticalToRF(P,Pmax,rfmax)
            rf = (asin((P/Pmax).^0.25)*2/pi).^2*rfmax;
        end
    end
    
end